output "url_publica" {
  description = "URL pública do MVP."
  value       = "https://${azurerm_container_app.app.ingress[0].fqdn}"
}

output "fqdn" {
  description = "Host para o targets/producao.json do Prometheus."
  value       = azurerm_container_app.app.ingress[0].fqdn
}

output "resource_group" {
  description = "Use como secret AZURE_RESOURCE_GROUP no GitHub."
  value       = azurerm_resource_group.rg.name
}

output "container_app" {
  description = "Use como secret AZURE_CONTAINERAPP_NAME no GitHub."
  value       = azurerm_container_app.app.name
}
