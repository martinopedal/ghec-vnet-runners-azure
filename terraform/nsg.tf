# -----------------------------------------------------------------------------
# Network Security Group
#
# The NSG enforces inbound isolation only. Outbound policy is the hub
# firewall's responsibility - all internet-bound traffic is routed there
# via UDR (0.0.0.0/0 -> VirtualAppliance). Azure's default outbound rules
# allow the traffic to flow to the firewall, which then applies the
# GitHub/GHE.com/Storage/Entra allowlists from CX doc Section 6.
#
# Why no outbound rules here:
#   NSG evaluates against the ORIGINAL destination, not the UDR next-hop.
#   With no DenyAllOutbound, Azure's implicit AllowInternetOutBound (65001)
#   lets traffic reach the UDR, which forwards it to the hub firewall.
#   Adding GitHub IP rules to the NSG would be redundant - the firewall
#   already enforces them. An explicit DenyAllOutbound would PREVENT traffic
#   from reaching the firewall at all, defeating the hub-spoke model.
#
# Inbound: GitHub injects runner NICs but never initiates connections.
# The default Azure AllowVNetInBound (65000) would permit lateral movement
# from peered workloads - block it explicitly.
#
# Ref: CX doc Section 4
# Ref: https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview
# -----------------------------------------------------------------------------

resource "azapi_resource" "nsg" {
  type      = "Microsoft.Network/networkSecurityGroups@2024-05-01"
  name      = var.nsg_name
  location  = var.location
  parent_id = var.resource_group_id
  tags      = local.tags

  body = {
    properties = {
      securityRules = [
        {
          name = "DenyAllInbound"
          properties = {
            priority                 = 100
            direction                = "Inbound"
            access                   = "Deny"
            protocol                 = "*"
            sourcePortRange          = "*"
            destinationPortRange     = "*"
            sourceAddressPrefix      = "*"
            destinationAddressPrefix = "*"
          }
        },
      ]
    }
  }
}