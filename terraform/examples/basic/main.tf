# -----------------------------------------------------------------------------
# Example: LZ Vending + GitHub Runner VNET Integration + GitHub App Auth
#
# Shows the full flow:
# 1. LZ vending creates the subscription, resource group, spoke VNET,
#    hub peering, and DNS configuration
# 2. This module adds the runner subnet, NSG, UDR, and networkSettings
# 3. GitHub App authentication fetches the org databaseId (no PATs)
#
# Prerequisites:
# - GitHub App installed on the target org with read:org scope
# - Azure CLI authenticated with Subscription Contributor + Network Contributor
# - GitHub.Network resource provider registered on the subscription
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.9"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "azapi" {}
provider "azurerm" {
  features {}
}

# -----------------------------------------------------------------------------
# GitHub App authentication - avoids PATs entirely.
# The app needs read:org scope on the target organization.
# -----------------------------------------------------------------------------

provider "github" {
  owner = var.github_organization
  app_auth {
    id              = var.github_app_id
    installation_id = var.github_app_installation_id
    pem_file        = var.github_app_pem_file
  }
}

data "github_organization" "this" {
  name = var.github_organization
}

# -----------------------------------------------------------------------------
# Landing Zone Vending
#
# Creates the subscription, resource group, spoke VNET, hub peering, and
# configures DNS to forward queries to the hub firewall DNS proxy.
# The VNET is placed in Sweden Central - a supported GHE.com EU region.
# -----------------------------------------------------------------------------

module "lz_vending" {
  source  = "Azure/lz-vending/azurerm"
  version = "~> 4.0"

  location = "swedencentral"

  subscription_alias_enabled = true
  subscription_alias_name    = "sub-ghrunners-prod"
  subscription_display_name  = "GitHub Runners - Production"
  subscription_billing_scope = var.billing_scope
  subscription_workload      = "Production"

  resource_groups = {
    rg-runners = {
      name     = "rg-ghrunners-swedencentral"
      location = "swedencentral"
    }
  }

  virtual_networks = {
    vnet-runners = {
      name          = "vnet-ghrunners-swedencentral"
      address_space = ["10.100.0.0/16"]

      resource_group_creation_enabled = false
      resource_group_name             = "rg-ghrunners-swedencentral"

      # Hub peering - connects spoke to hub in Norway East
      hub_peering_enabled               = true
      hub_network_resource_id           = var.hub_vnet_id
      hub_peering_use_remote_gateways   = var.enable_gateway_transit
      hub_peering_allow_gateway_transit = var.enable_gateway_transit

      # DNS - point spoke at hub so runners resolve private endpoints
      # in Norway East (e.g. *.privatelink.blob.core.windows.net)
      dns_servers = var.hub_dns_servers
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# GitHub Runner Infrastructure
#
# Adds the runner-specific resources on top of the vended landing zone:
# subnet (delegated), NSG (GHE.com EU IPs), UDR (hub egress), networkSettings.
# -----------------------------------------------------------------------------

module "github_runners" {
  source = "../../terraform"

  resource_group_id       = module.lz_vending.resource_group_resource_ids["rg-runners"]
  virtual_network_id      = module.lz_vending.virtual_network_resource_ids["vnet-runners"]
  location                = "swedencentral"
  subnet_address_prefix   = "10.100.0.0/24"
  hub_firewall_private_ip = var.hub_firewall_private_ip
  github_business_id      = tostring(data.github_organization.this.id)

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "github_organization" {
  type        = string
  description = "GitHub organization login name."
}

variable "github_app_id" {
  type      = string
  sensitive = true
}

variable "github_app_installation_id" {
  type      = string
  sensitive = true
}

variable "github_app_pem_file" {
  type      = string
  sensitive = true
}

variable "hub_vnet_id" {
  type        = string
  description = "Full resource ID of the hub VNET in Norway East."
}

variable "hub_firewall_private_ip" {
  type        = string
  description = "Private IP of the hub firewall."
}

variable "hub_dns_servers" {
  type        = list(string)
  description = "Hub DNS server IPs (firewall DNS proxy or Private Resolver)."
  default     = []
}

variable "enable_gateway_transit" {
  type    = bool
  default = false
}

variable "billing_scope" {
  type        = string
  description = "Billing scope for subscription creation."
}

variable "tags" {
  type    = map(string)
  default = {}
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "github_id" {
  description = "Paste this into GHE.com → Enterprise Settings → Hosted compute networking."
  value       = module.github_runners.github_id
}

output "subnet_id" {
  value = module.github_runners.subnet_id
}

output "subscription_id" {
  value = module.lz_vending.subscription_id
}
