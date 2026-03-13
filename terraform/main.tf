# -----------------------------------------------------------------------------
# Runner Subnet
#
# Created inside the VNET provisioned by the LZ vending module.
# Delegated exclusively to GitHub.Network/networkSettings - no other NICs or
# services may coexist. A service association link is applied automatically
# by the GitHub.Network RP, preventing accidental deletion while in use.
#
# NSG and route table are associated at creation to ensure the subnet is
# never exposed without security controls.
#
# CX doc Sections 3, 8
# -----------------------------------------------------------------------------

resource "azapi_resource" "subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = var.subnet_name
  parent_id = var.virtual_network_id

  body = {
    properties = {
      addressPrefix = var.subnet_address_prefix
      delegations = [
        {
          name = "github-network-delegation"
          properties = {
            serviceName = "GitHub.Network/networkSettings"
          }
        }
      ]
      networkSecurityGroup = {
        id = azapi_resource.nsg.id
      }
      routeTable = {
        id = azapi_resource.route_table.id
      }
    }
  }

  depends_on = [
    azapi_resource.nsg,
    azapi_resource.route_table,
  ]
}
