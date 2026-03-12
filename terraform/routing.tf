# -----------------------------------------------------------------------------
# Route Table
#
# Forces all internet-bound egress through the hub firewall via UDR.
# This replaces the need for a NAT Gateway — the hub firewall handles SNAT
# and outbound policy enforcement.
#
# BGP propagation is left enabled so gateway routes (VPN/ER) advertised by
# the hub can propagate into the spoke. Disable if you need full UDR control
# without BGP interference.
#
# CX doc Section 5
# -----------------------------------------------------------------------------

resource "azapi_resource" "route_table" {
  type      = "Microsoft.Network/routeTables@2024-05-01"
  name      = var.route_table_name
  location  = var.location
  parent_id = var.resource_group_id
  tags      = local.tags

  body = {
    properties = {
      disableBgpRoutePropagation = false
      routes = [
        {
          name = "default-to-hub-firewall"
          properties = {
            addressPrefix    = "0.0.0.0/0"
            nextHopType      = "VirtualAppliance"
            nextHopIpAddress = var.hub_firewall_private_ip
          }
        },
      ]
    }
  }
}
