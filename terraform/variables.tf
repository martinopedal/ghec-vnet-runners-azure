# -----------------------------------------------------------------------------
# Inputs from Landing Zone Vending
#
# These map directly to the outputs of the Azure/lz-vending/azurerm module:
#   resource_group_id  ← module.lz_vending.resource_group_resource_ids["key"]
#   virtual_network_id ← module.lz_vending.virtual_network_resource_ids["key"]
# -----------------------------------------------------------------------------

variable "resource_group_id" {
  type        = string
  description = "Full resource ID of the resource group created by LZ vending."
}

variable "virtual_network_id" {
  type        = string
  description = "Full resource ID of the spoke VNET created by LZ vending. Must be in a supported GHE.com EU region."
}

# -----------------------------------------------------------------------------
# Region
#
# Must match the VNET location. Defaults to swedencentral — the most common
# choice for Nordic customers. Override if the vending module placed the VNET
# in a different supported EU region.
# -----------------------------------------------------------------------------

variable "location" {
  type        = string
  description = "Azure region. Must match the VNET region and be a supported GHE.com EU region."
  default     = "swedencentral"

  validation {
    condition     = contains(["francecentral", "swedencentral", "germanywestcentral", "northeurope", "italynorth"], var.location)
    error_message = "Must be a supported GHE.com EU region: francecentral, swedencentral, germanywestcentral, northeurope, or italynorth."
  }
}

# -----------------------------------------------------------------------------
# Subnet
# -----------------------------------------------------------------------------

variable "subnet_name" {
  type        = string
  description = "Name of the dedicated GitHub runner subnet."
  default     = "snet-github-runners"
}

variable "subnet_address_prefix" {
  type        = string
  description = "CIDR for the runner subnet. /24 minimum recommended (max concurrency + 30 pct buffer)."
}

# -----------------------------------------------------------------------------
# Hub Connectivity
# The hub VNET and peering are created by LZ vending. The module only needs
# the firewall IP for the UDR next-hop.
# -----------------------------------------------------------------------------

variable "hub_firewall_private_ip" {
  type        = string
  description = "Private IP of the hub firewall or NVA. Used as next-hop in the default route."
}

# -----------------------------------------------------------------------------
# GitHub
# -----------------------------------------------------------------------------

variable "github_business_id" {
  type        = string
  description = "GitHub enterprise or organization databaseId. Obtain via GraphQL API or the GitHub Terraform provider."
}

variable "network_settings_name" {
  type        = string
  description = "Name of the GitHub.Network/networkSettings resource."
  default     = "ghrunners-network-settings"
}

# -----------------------------------------------------------------------------
# NSG
# -----------------------------------------------------------------------------

variable "nsg_name" {
  type        = string
  description = "Name of the Network Security Group for the runner subnet."
  default     = "nsg-github-runners"
}

# -----------------------------------------------------------------------------
# Routing
# -----------------------------------------------------------------------------

variable "route_table_name" {
  type        = string
  description = "Name of the route table for the runner subnet."
  default     = "rt-github-runners"
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources created by this module."
  default     = {}
}
