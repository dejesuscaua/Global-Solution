output "url_publica" {
  description = "URL pública do MVP."
  value       = "https://${azurerm_container_app.app.ingress[0].fqdn}"
}

output "fqdn" {
  description = "Host para o targets/producao.json do Prometheus."
  value       = azurerm_container_app.app.ingress[0].fqdn
}

output "resource_group" {
  description = "Variable AZURE_RESOURCE_GROUP no GitHub."
  value       = azurerm_resource_group.rg.name
}

output "container_app" {
  description = "Variable AZURE_CONTAINERAPP_NAME no GitHub."
  value       = azurerm_container_app.app.name
}

output "azure_client_id" {
  description = "Variable AZURE_CLIENT_ID no GitHub (identidade do deploy, sem senha)."
  value       = azurerm_user_assigned_identity.deploy.client_id
}

output "azure_tenant_id" {
  description = "Variable AZURE_TENANT_ID no GitHub."
  value       = data.azurerm_client_config.atual.tenant_id
}

output "azure_subscription_id" {
  description = "Variable AZURE_SUBSCRIPTION_ID no GitHub."
  value       = data.azurerm_client_config.atual.subscription_id
}
