<!-- BEGIN_TF_DOCS -->

# GitHub-Hosted Runners VNET Integration for GHE.com (EU Data Residency)

Terraform module that provisions the Azure-side infrastructure needed for
VNET-integrated GitHub-hosted runners on GitHub Enterprise Cloud with EU
data residency (GHE.com).

Designed to consume resources created by the
[Azure Landing Zone Vending module](https://registry.terraform.io/modules/Azure/lz-vending/azurerm/latest)
— the subscription, resource group, spoke VNET, hub peering, and DNS are all
pre-existing. This module adds only what the vending module does not provide:
a dedicated runner subnet, a locked-down NSG, a UDR for hub egress, and the
`GitHub.Network/networkSettings` resource that links everything to GHE.com.

Built with the [AzAPI provider](https://registry.terraform.io/providers/Azure/azapi/latest/docs)
for direct ARM API access to `GitHub.Network/networkSettings`.

## What LZ Vending Creates vs. What This Module Creates

| Resource | Created by | Notes |
|----------|-----------|-------|
| Subscription | LZ Vending | With GitHub.Network RP registered |
| Resource Group | LZ Vending | In Sweden Central (or other supported region) |
| Spoke VNET | LZ Vending | With DNS pointing to hub (firewall DNS proxy / Private Resolver) |
| VNET Peering to hub | LZ Vending | Bidirectional, with gateway transit if needed |
| **Runner Subnet** | **This module** | Delegated to GitHub.Network/networkSettings |
| **NSG** | **This module** | GHE.com EU IP allowlists, deny-by-default |
| **Route Table** | **This module** | 0.0.0.0/0 → hub firewall |
| **GitHub.Network/networkSettings** | **This module** | Links subnet to GHE.com enterprise/org |

## Architecture

```
┌──────────────────────────────────────┐
│         Norway East (Hub)            │
│  ┌────────────────────────────────┐  │
│  │  Hub VNET                      │  │
│  │  - Azure Firewall / NVA        │  │
│  │  - DNS (Priv. Resolver / Proxy)│  │
│  │  - Private Endpoints           │  │
│  └──────────┬─────────────────────┘  │
└─────────────┼────────────────────────┘
              │  Peering (from LZ Vending)
┌─────────────┼────────────────────────┐
│  Sweden Central (Spoke from Vending) │
│  ┌──────────┴─────────────────────┐  │
│  │  Spoke VNET (LZ Vending)       │  │
│  │  DNS → Hub DNS servers         │  │
│  │  ┌──────────────────────────┐  │  │
│  │  │ snet-github-runners      │  │  │
│  │  │ ← This module creates    │  │  │
│  │  │ Delegation: GitHub.Network│ │  │
│  │  │ NSG + UDR attached       │  │  │
│  │  └──────────────────────────┘  │  │
│  └────────────────────────────────┘  │
│  ┌────────────────────────────────┐  │
│  │ GitHub.Network/networkSettings │  │
│  │ ← This module creates          │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

## Supported Regions (GHE.com EU)

| Runner Type | Supported Regions |
|-------------|---------------------------------------------------|
| x64 | francecentral, swedencentral, germanywestcentral, northeurope |
| arm64 | francecentral, northeurope, germanywestcentral |
| GPU | italynorth, swedencentral |

Norway East is **not** supported for GHE.com with EU data residency.
Default is `swedencentral` — override if the vending module placed the VNET
in a different supported region.

## Prerequisites

1. **LZ Vending module** has run and created the subscription, resource group,
   spoke VNET (in a supported EU region), and hub peering
2. `GitHub.Network` resource provider registered on the subscription:
   ```bash
   az provider register --namespace GitHub.Network
   ```
3. Azure RBAC: **Subscription Contributor** and **Network Contributor**
4. GitHub enterprise or organization `databaseId`
5. Hub DNS configured so the spoke VNET resolves private endpoint FQDNs
   (Azure Firewall DNS Proxy, Azure DNS Private Resolver, or custom forwarders)
6. Hub firewall must **not** TLS-inspect traffic to GitHub/GHE.com endpoints

## Usage

### With LZ Vending Module

```terraform
# --- Landing Zone Vending creates the subscription, RG, VNET, peering, DNS ---
module "lz_vending" {
  source  = "Azure/lz-vending/azurerm"
  version = "~> 4.0"

  location = "swedencentral"

  # Subscription
  subscription_alias_enabled = true
  subscription_alias_name    = "sub-ghrunners-prod"
  subscription_display_name  = "GitHub Runners - Production"
  subscription_billing_scope = "/providers/..."
  subscription_workload      = "Production"

  # Resource groups
  resource_groups = {
    rg-runners = {
      name     = "rg-ghrunners-swedencentral"
      location = "swedencentral"
    }
  }

  # Networking — spoke VNET with hub peering and DNS
  virtual_networks = {
    vnet-runners = {
      name          = "vnet-ghrunners-swedencentral"
      address_space = ["10.100.0.0/16"]
      resource_group_creation_enabled = false
      resource_group_name             = "rg-ghrunners-swedencentral"

      # Hub peering
      hub_peering_enabled              = true
      hub_network_resource_id          = "/subscriptions/.../virtualNetworks/vnet-hub-norwayeast"
      hub_peering_use_remote_gateways  = true
      hub_peering_allow_gateway_transit = true

      # DNS — point spoke at hub DNS so runners resolve private endpoints
      dns_servers = ["10.0.1.4"]  # Hub firewall DNS proxy IP
    }
  }
}

# --- This module adds the runner-specific infrastructure ---
module "github_runners" {
  source = "./terraform"

  resource_group_id       = module.lz_vending.resource_group_resource_ids["rg-runners"]
  virtual_network_id      = module.lz_vending.virtual_network_resource_ids["vnet-runners"]
  location                = "swedencentral"
  subnet_address_prefix   = "10.100.0.0/24"
  hub_firewall_private_ip = "10.0.1.4"
  github_business_id      = tostring(data.github_organization.this.id)

  tags = {
    environment = "production"
    team        = "platform-engineering"
  }
}
```

### Fetching the GitHub databaseId with a GitHub App

```terraform
provider "github" {
  owner = "my-org"
  app_auth {
    id              = var.github_app_id
    installation_id = var.github_app_installation_id
    pem_file        = var.github_app_pem_file
  }
}

data "github_organization" "this" {
  name = "my-org"
}

# Pass to the module:
# github_business_id = tostring(data.github_organization.this.id)
```

## DNS — How Hub Resolution Works

The LZ vending module configures `dns_servers` on the spoke VNET, forwarding
all DNS queries to the hub. This is required when runners need to resolve:

- Private endpoint FQDNs (e.g. `*.privatelink.blob.core.windows.net`)
- On-premises hostnames reachable through the hub
- Custom DNS zones hosted in the hub

| Hub DNS Type | What to configure as dns_servers |
|---|---|
| Azure Firewall DNS Proxy | Firewall private IP |
| Azure DNS Private Resolver | Inbound endpoint IP |
| Custom DNS VMs | Forwarder VM IPs |

## TLS Interception

Outbound traffic from the runner subnet **must not** be subject to TLS
inspection. GitHub runner VMs do not trust intermediate certificates. Exclude
GitHub and GHE.com traffic from TLS inspection policy on the hub firewall,
or use custom runner images with pre-installed certificates.

Reference: CX doc Section 7

## NSG Design

The NSG enforces **inbound isolation only**. Outbound policy is the hub firewall's
job — all internet-bound traffic reaches it via UDR. Azure's default
AllowInternetOutBound (65001) lets traffic flow to the firewall, which applies the
GitHub/GHE.com/Storage/Entra allowlists documented in
[CX doc Section 6](../docs/customer-ready-en.md#6-hub-firewall-requirements).

| Priority | Name | Direction | Action | Purpose |
|----------|------|-----------|--------|---------|
| 100 | DenyAllInbound | Inbound | Deny | GitHub never needs inbound access |

No outbound NSG rules are needed — adding them would be redundant with the firewall.
An explicit DenyAllOutbound would prevent traffic from reaching the firewall entirely.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9 |
| azapi | ~> 2.0 |

## Resources

| Name | Type |
|------|------|
| `azapi_resource.subnet` | Microsoft.Network/virtualNetworks/subnets |
| `azapi_resource.nsg` | Microsoft.Network/networkSecurityGroups |
| `azapi_resource.route_table` | Microsoft.Network/routeTables |
| `azapi_resource.network_settings` | GitHub.Network/networkSettings |

## Required Inputs

### <a name="input_resource_group_id"></a> [resource\_group\_id](#input_resource_group_id)

Description: Full resource ID of the resource group created by LZ vending.

Type: `string`

### <a name="input_virtual_network_id"></a> [virtual\_network\_id](#input_virtual_network_id)

Description: Full resource ID of the spoke VNET created by LZ vending.

Type: `string`

### <a name="input_subnet_address_prefix"></a> [subnet\_address\_prefix](#input_subnet_address_prefix)

Description: CIDR for the runner subnet. /24 minimum recommended.

Type: `string`

### <a name="input_hub_firewall_private_ip"></a> [hub\_firewall\_private\_ip](#input_hub_firewall_private_ip)

Description: Private IP of the hub firewall or NVA used as UDR next-hop.

Type: `string`

### <a name="input_github_business_id"></a> [github\_business\_id](#input_github_business_id)

Description: GitHub enterprise or organization databaseId.

Type: `string`

## Optional Inputs

### <a name="input_location"></a> [location](#input_location)

Description: Azure region. Must match the VNET and be a supported GHE.com EU region.

Type: `string`

Default: `"swedencentral"`

### <a name="input_subnet_name"></a> [subnet\_name](#input_subnet_name)

Description: Name of the dedicated runner subnet.

Type: `string`

Default: `"snet-github-runners"`

### <a name="input_nsg_name"></a> [nsg\_name](#input_nsg_name)

Description: Name of the NSG.

Type: `string`

Default: `"nsg-github-runners"`

### <a name="input_route_table_name"></a> [route\_table\_name](#input_route_table_name)

Description: Name of the route table.

Type: `string`

Default: `"rt-github-runners"`

### <a name="input_network_settings_name"></a> [network\_settings\_name](#input_network_settings_name)

Description: Name of the GitHub.Network/networkSettings resource.

Type: `string`

Default: `"ghrunners-network-settings"`

### <a name="input_tags"></a> [tags](#input_tags)

Description: Tags applied to all resources.

Type: `map(string)`

Default: `{}`

## Outputs

### <a name="output_subnet_id"></a> [subnet\_id](#output_subnet_id)

Description: Resource ID of the delegated runner subnet.

### <a name="output_nsg_id"></a> [nsg\_id](#output_nsg_id)

Description: Resource ID of the Network Security Group.

### <a name="output_route_table_id"></a> [route\_table\_id](#output_route_table_id)

Description: Resource ID of the route table.

### <a name="output_network_settings_id"></a> [network\_settings\_id](#output_network_settings_id)

Description: Resource ID of the GitHub.Network/networkSettings resource.

### <a name="output_github_id"></a> [github\_id](#output_github_id)

Description: GitHubId to paste into the GHE.com network configuration UI.

## References

- [GHE.com Network Details](https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/network-details-for-ghecom)
- [Configuring Private Networking (Enterprise)](https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/configuring-private-networking-for-github-hosted-runners-in-your-enterprise)
- [Azure Subnet Delegation](https://learn.microsoft.com/azure/virtual-network/subnet-delegation-overview)
- [Azure DNS Private Resolver](https://learn.microsoft.com/azure/dns/dns-private-resolver-overview)
- [Hub-Spoke Topology](https://learn.microsoft.com/azure/architecture/networking/architecture/hub-spoke)
- [LZ Vending Module](https://registry.terraform.io/modules/Azure/lz-vending/azurerm/latest)
- [AzAPI Provider](https://registry.terraform.io/providers/Azure/azapi/latest/docs)

<!-- END_TF_DOCS -->
