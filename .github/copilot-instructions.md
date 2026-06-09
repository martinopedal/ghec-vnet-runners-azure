# Contributor Guide - GHEC VNET Runners Azure

## What this module does

Provisions Azure networking infrastructure for VNET-integrated GitHub-hosted runners on GitHub Enterprise Cloud with EU data residency. Uses the AzAPI provider exclusively for direct ARM API access to `GitHub.Network/networkSettings`.

## Development workflow

```bash
cd terraform
terraform init              # Download providers
terraform validate          # Syntax + type check
terraform fmt -recursive    # Format all .tf files
terraform plan              # Preview changes
```

Run `terraform validate` after every code modification before committing.

## Documentation references

When updating IP ranges, supported regions, or feature claims, validate against the latest official documentation:

- [GHE.com Network Details](https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/network-details-for-ghecom)
- [Configuring Private Networking (Enterprise)](https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/configuring-private-networking-for-github-hosted-runners-in-your-enterprise)
- [About Azure Private Networking for Runners](https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/about-azure-private-networking-for-github-hosted-runners-in-your-enterprise)
- [GitHub.Network/networkSettings ARM Schema](https://learn.microsoft.com/azure/templates/github.network/2024-04-02/networksettings)
- [Azure Subnet Delegation](https://learn.microsoft.com/azure/virtual-network/subnet-delegation-overview)
- [Hub-Spoke Network Topology](https://learn.microsoft.com/azure/architecture/networking/architecture/hub-spoke)

## Architecture

The module creates four resources:

1. **Runner Subnet** (`main.tf`) - delegated to `GitHub.Network/networkSettings`, NSG + UDR attached at creation
2. **NSG** (`nsg.tf`) - inbound deny-all only; outbound policy is the hub firewall's responsibility
3. **Route Table** (`routing.tf`) - `0.0.0.0/0` next-hop to hub firewall
4. **GitHub.Network/networkSettings** (`network_settings.tf`) - links the subnet to GHE.com

### Key design decisions

- **No outbound NSG rules**: Azure evaluates NSG rules against the original destination, not the UDR next-hop. The default `AllowInternetOutBound` (priority 65001) lets traffic reach the UDR. Adding an explicit `DenyAllOutbound` would prevent traffic from reaching the firewall entirely.
- **schema_validation_enabled = false** on `network_settings`: The AzAPI provider does not ship a built-in schema for `GitHub.Network`. Tracked at [Azure/terraform-provider-azapi#447](https://github.com/Azure/terraform-provider-azapi/issues/447).
- **Region validation**: The `location` variable validates against supported GHE.com EU regions. Norway East is NOT supported despite being listed on github.com (different backend infrastructure).

## File layout

| File | Purpose |
|---|---|
| `terraform/versions.tf` | Terraform and provider version constraints |
| `terraform/variables.tf` | Input variables with validation |
| `terraform/locals.tf` | GHE.com IP ranges, computed tags |
| `terraform/main.tf` | Runner subnet |
| `terraform/nsg.tf` | Network Security Group |
| `terraform/routing.tf` | Route table with UDR |
| `terraform/network_settings.tf` | `GitHub.Network/networkSettings` |
| `terraform/outputs.tf` | Module outputs |
| `docs/` | Customer-facing documentation |

New resources go in the file matching their category.

## Code conventions

### AzAPI-only

All Azure resources use `azapi_resource`. Do not introduce `azurerm_*` resources. When adding resources:

1. Find the ARM resource type and latest stable API version
2. Use `azapi_resource` with HCL `body = { ... }` syntax (not `jsonencode`)
3. Set `schema_validation_enabled = false` only when the provider lacks the schema

### Variables

- Every variable has `description`, `type`, and `default` (where applicable)
- Use `validation {}` blocks for enums (see `location` in `variables.tf`)
- Group variables by section with `# ----` comment headers

### Tags

All resources receive `local.tags`. Don't hardcode tags on individual resources.

### IP ranges

The GHE.com IP ranges in `locals.tf` are sourced from GitHub documentation. Keep in sync with the official [GHE.com network details](https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/network-details-for-ghecom).

## Pre-commit checklist

1. `cd terraform && terraform init && terraform validate` passes
2. `terraform fmt -check -recursive` passes
3. Mermaid diagrams in README.md render correctly on GitHub
4. IP ranges validated against current GitHub documentation
5. NSG rules follow the design (inbound deny-all only, no outbound rules)
6. Supported regions list matches current GHE.com documentation
7. Customer-ready docs (`docs/`) are consistent with README
