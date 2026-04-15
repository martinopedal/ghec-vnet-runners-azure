# Third-Party Notices

This module depends on the Terraform providers listed below. It does not source any
AVM registry modules directly — all Azure resources are provisioned via the `azapi` provider.
The module is designed to consume outputs from AVM Landing Zone modules
(e.g. [`Azure/lz-vending/azurerm`](https://registry.terraform.io/modules/Azure/lz-vending/azurerm/latest))
but does not include them as dependencies.

---

## Azure Verified Modules (AVM)

- **Specification & Guidelines:** https://aka.ms/avm
- **Registry:** https://registry.terraform.io/namespaces/Azure
- **License:** MIT License

This module does not source AVM registry modules directly. It is designed to be used
alongside AVM Landing Zone (lz-vending) deployments, accepting the resource group ID
and virtual network ID as inputs.

---

## HashiCorp Terraform Providers

- **azapi provider:** https://github.com/Azure/terraform-provider-azapi (MPL-2.0)
- **Providers are downloaded at `terraform init` time and are not bundled in this repository.**

> **Note on MPL-2.0:** The Mozilla Public License 2.0 is a weak copyleft license that applies
> only to the provider source files themselves, not to Terraform configurations that use the
> provider. Using these providers in your Terraform code does not impose any license requirements
> on your own configuration code.

---

## AVM Specification

- **Source:** https://azure.github.io/Azure-Verified-Modules/
- **Copyright:** Copyright (c) Microsoft Corporation
- **License:** MIT License