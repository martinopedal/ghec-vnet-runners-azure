# Copilot Instructions – GHEC VNET Runners Azure (azapi)

## What this repo is

A Terraform module that provisions Azure-side infrastructure for **VNET-integrated GitHub-hosted runners** on **GitHub Enterprise Cloud with EU data residency (GHE.com)**. Uses the **azapi provider** exclusively for all Azure resource creation. Designed to layer on top of the [Azure Landing Zone Vending module](https://registry.terraform.io/modules/Azure/lz-vending/azurerm/latest).

## Commands

```bash
cd terraform
terraform init              # Download providers
terraform validate          # Syntax + type check (run after every change)
terraform fmt -recursive    # Format all .tf files
terraform plan              # Preview changes (requires Azure auth)
terraform apply             # Deploy (requires Azure auth)
```

No test framework is configured. Validate changes with `terraform validate`. Always run `terraform validate` after any code modification before committing.

## Documentation Sources

Always fetch the latest documentation from official sources before making claims about GHE.com features, supported regions, IP ranges, or limitations. Do not rely on training data or cached knowledge.

Key sources to validate against:
- [GHE.com Network Details](https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/network-details-for-ghecom)
- [Configuring Private Networking (Enterprise)](https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/configuring-private-networking-for-github-hosted-runners-in-your-enterprise)
- [About Azure Private Networking for Runners](https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/about-azure-private-networking-for-github-hosted-runners-in-your-enterprise)
- [Troubleshooting Private Networking](https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/troubleshooting-azure-private-network-configurations-for-github-hosted-runners-in-your-enterprise)
- [GitHub.Network/networkSettings ARM Schema](https://learn.microsoft.com/azure/templates/github.network/2024-04-02/networksettings)
- [Azure Subnet Delegation](https://learn.microsoft.com/azure/virtual-network/subnet-delegation-overview)
- [Hub-Spoke Network Topology](https://learn.microsoft.com/azure/architecture/networking/architecture/hub-spoke)

Use the `azure-mcp-documentation` MCP tool with `microsoft_docs_fetch` to retrieve current page content when validating claims.

## Architecture

The module creates four resources on top of a pre-existing spoke VNET from LZ vending:

1. **Runner Subnet** (`main.tf`) - delegated to `GitHub.Network/networkSettings`, NSG + UDR attached at creation
2. **NSG** (`nsg.tf`) - inbound deny-all only; outbound policy is the hub firewall's responsibility
3. **Route Table** (`routing.tf`) - `0.0.0.0/0` next-hop to hub firewall (UDR)
4. **GitHub.Network/networkSettings** (`network_settings.tf`) - links the subnet to GHE.com enterprise/org

### Key design decisions

- **No outbound NSG rules**: Azure evaluates NSG rules against the original destination, not the UDR next-hop. The default `AllowInternetOutBound` (priority 65001) lets traffic reach the UDR, which forwards to the hub firewall. Adding an explicit `DenyAllOutbound` would prevent traffic from reaching the firewall entirely.
- **schema_validation_enabled = false** on `network_settings`: The AzAPI provider does not ship a built-in schema for `GitHub.Network`. Tracked at [Azure/terraform-provider-azapi#447](https://github.com/Azure/terraform-provider-azapi/issues/447).
- **Region validation**: The `location` variable validates against supported GHE.com EU regions. Norway East is NOT supported despite being listed on github.com (different backend infrastructure).

## File Layout

| File | Contains |
|---|---|
| `terraform/versions.tf` | `terraform {}` block, required providers |
| `terraform/variables.tf` | All input variables, grouped by section |
| `terraform/locals.tf` | GHE.com IP ranges, computed tags |
| `terraform/main.tf` | Runner subnet resource |
| `terraform/nsg.tf` | Network Security Group |
| `terraform/routing.tf` | Route table with UDR |
| `terraform/network_settings.tf` | `GitHub.Network/networkSettings` resource |
| `terraform/outputs.tf` | All outputs |
| `terraform/examples/basic/` | Full example with LZ vending + GitHub App auth |
| `docs/customer-ready-en.md` | Customer-facing infra requirements (English) |
| `docs/customer-ready-no.md` | Customer-facing infra requirements (Norwegian) |

New resources go in the file matching their category. Don't create new `.tf` files unless adding a genuinely separate concern.

## Conventions

### azapi-only resources

All Azure resources use `azapi_resource`. Do **not** introduce `azurerm_*` resources. When adding new Azure resources:

1. Find the ARM resource type and latest stable API version.
2. Use `azapi_resource` with HCL `body = { ... }` syntax (not `jsonencode`).
3. Set `schema_validation_enabled = false` only when the provider lacks the schema.

### Variable style

- Every variable has `description`, `type`, and `default` (where applicable).
- Use `validation {}` blocks for enums (see `location` in `variables.tf`).
- Group variables by section with `# ----` comment headers.

### Tags

All resources receive `local.tags`. Don't hardcode tags on individual resources.

### IP ranges in locals.tf

The GHE.com IP ranges in `locals.tf` are sourced from the GitHub documentation. These **must be kept in sync** with the official [GHE.com network details](https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/network-details-for-ghecom). Verify against the docs page before any production deployment.

## Validation Checklist

Before committing changes:

1. `cd terraform && terraform init && terraform validate` - all code changes must pass
2. `terraform fmt -check -recursive` - formatting must be consistent
3. Verify Mermaid diagrams in README.md render correctly on GitHub
4. Validate GHE.com IP ranges against current documentation using `azure-mcp-documentation` or `web_fetch`
5. Check that NSG rules follow the design (inbound deny-all only, no outbound rules)
6. Confirm supported regions list matches current GHE.com documentation
7. Ensure customer-ready docs (`docs/`) are consistent with README content
8. Cross-reference firewall rules against [GHE.com network details](https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/network-details-for-ghecom)
