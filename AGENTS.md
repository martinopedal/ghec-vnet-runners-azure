# AI Agent Instructions

## Repository Purpose

This module deploys GitHub-hosted runners with Azure VNET integration, optimized for GHE.com EU data residency.

## Module Usage

- ✅ All infrastructure is Terraform (HCL)
- ✅ Runner subnet is delegated to `GitHub.Network/networkSettings`
- ✅ NSG + UDR attached at subnet creation
- ✅ Route table sends 0.0.0.0/0 to hub firewall
- ✅ No public IP - egress through central Azure Firewall

## Code Quality

- ✅ Run `terraform fmt -check -recursive` before committing
- ✅ Run `terraform validate` before committing
- ✅ Follow existing file naming conventions
- ✅ Only use checkmarks in documentation lists, no AI language or em dashes
