# ghec-vnet-runners-azure

Terraform module and customer documentation for deploying VNET-integrated
GitHub-hosted runners on **GitHub Enterprise Cloud with EU data residency**
(GHE.com).

## Problem

GHE.com with EU data residency does not support Norway East as a VNET region
for GitHub-hosted runners. The closest supported region for Nordic customers
is **Sweden Central**. This repository provides the Azure infrastructure
(as a Terraform module) and operational documentation needed to deploy runners
in Sweden Central while keeping primary workloads in Norway East, connected
through a hub-spoke topology provisioned by the
[Azure Landing Zone Vending module](https://registry.terraform.io/modules/Azure/lz-vending/azurerm/latest).

## Contents

```
├── docs/
│   ├── customer-ready-en.md        # English — full requirements, NSG matrix, UDR, firewall, DNS
│   └── customer-ready-no.md        # Norwegian — same content, technical terms in English
├── terraform/
│   ├── main.tf                     # Runner subnet (delegated to GitHub.Network)
│   ├── nsg.tf                      # NSG with GHE.com EU IP allowlists
│   ├── routing.tf                  # UDR → hub firewall
│   ├── network_settings.tf         # GitHub.Network/networkSettings
│   ├── variables.tf                # Inputs (takes LZ vending outputs)
│   ├── locals.tf                   # GHE.com EU IP lists
│   ├── outputs.tf                  # GitHubId + resource IDs
│   ├── versions.tf                 # AzAPI ~> 2.0
│   ├── README.md                   # AVM-style module documentation
│   └── examples/
│       └── basic/main.tf           # LZ Vending + this module + GitHub App auth
└── README.md                       # This file
```

## Design

The module assumes the
[Azure Landing Zone Vending module](https://registry.terraform.io/modules/Azure/lz-vending/azurerm/latest)
has already created:

| Pre-existing (from LZ Vending) | This module creates |
|---|---|
| Subscription | Runner subnet (delegated) |
| Resource Group | NSG (deny-by-default, GHE.com EU IPs) |
| Spoke VNET (Sweden Central) | Route Table (0.0.0.0/0 → hub FW) |
| Hub peering (bidirectional) | GitHub.Network/networkSettings |
| DNS (pointing to hub) | |

## Quick Start

```bash
# 1. Register the GitHub.Network resource provider
az provider register --namespace GitHub.Network

# 2. Deploy (see terraform/examples/basic/ for full example)
cd terraform
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan

# 3. Copy the github_id output into:
#    GHE.com → Enterprise Settings → Hosted compute networking → New network configuration
```

## Supported Regions (GHE.com EU)

| Runner Type | Regions |
|-------------|---------|
| x64 | francecentral, swedencentral, germanywestcentral, northeurope |
| arm64 | francecentral, northeurope, germanywestcentral |
| GPU | italynorth, swedencentral |

## References

- [GHE.com Network Details](https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/network-details-for-ghecom)
- [Configuring Private Networking for Runners](https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/configuring-private-networking-for-github-hosted-runners-in-your-enterprise)
- [LZ Vending Module](https://registry.terraform.io/modules/Azure/lz-vending/azurerm/latest)
- [AzAPI Provider](https://registry.terraform.io/providers/Azure/azapi/latest/docs)

## License

MIT
