output "subnet_id" {
  description = "Resource ID of the delegated runner subnet."
  value       = azapi_resource.subnet.id
}

output "nsg_id" {
  description = "Resource ID of the Network Security Group."
  value       = azapi_resource.nsg.id
}

output "route_table_id" {
  description = "Resource ID of the route table."
  value       = azapi_resource.route_table.id
}

output "network_settings_id" {
  description = "Resource ID of the GitHub.Network/networkSettings resource."
  value       = azapi_resource.network_settings.id
}

output "github_id" {
  description = "GitHubId from the networkSettings resource. Paste this into the GHE.com network configuration UI."
  value       = azapi_resource.network_settings.output.tags.GitHubId
}
