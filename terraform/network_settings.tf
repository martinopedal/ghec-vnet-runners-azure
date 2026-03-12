# -----------------------------------------------------------------------------
# GitHub.Network/networkSettings
#
# The Azure-side resource that links a delegated subnet to a GitHub enterprise
# or organization. The GitHub Actions runner service reads this to determine
# where to inject runner NICs.
#
# The GitHubId tag on the created resource is the value you paste into:
#   GHE.com → Enterprise Settings → Hosted compute networking → New network configuration
#
# schema_validation_enabled is off because the AzAPI provider does not ship
# a built-in schema for GitHub.Network. Deployments work fine regardless.
# Tracked: https://github.com/Azure/terraform-provider-azapi/issues/447
# Schema:  https://learn.microsoft.com/azure/templates/github.network/2024-04-02/networksettings
# -----------------------------------------------------------------------------

resource "azapi_resource" "network_settings" {
  type      = "GitHub.Network/networkSettings@2024-04-02"
  name      = var.network_settings_name
  location  = var.location
  parent_id = var.resource_group_id
  tags      = local.tags

  schema_validation_enabled = false

  body = {
    properties = {
      subnetId   = azapi_resource.subnet.id
      businessId = var.github_business_id
    }
  }

  response_export_values = ["tags.GitHubId"]

  depends_on = [
    azapi_resource.subnet,
  ]
}
