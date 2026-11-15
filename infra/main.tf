# Infraestrutura da vitrine SeguWatts no Azure App Service (Linux, plano F1 gratuito).
#
# Decisões de segurança:
# - Não existe VM, SSH ou RDP. O único ponto de entrada público é o HTTPS gerenciado (443)
#   em *.azurewebsites.net, com redirecionamento obrigatório de HTTP para HTTPS e TLS 1.2+.
# - O painel de administração (Kudu/SCM) nega acesso a qualquer IP por padrão
#   (scm_ip_restriction_default_action = "Deny"): não fica aberto para 0.0.0.0/0.
# - FTP e publicação com usuário/senha (basic auth) desligados: o único caminho de deploy
#   é o pipeline, autenticado por OIDC (ver identidade.tf).
# - O token de métricas é uma app setting (criptografada em repouso pelo Azure), vinda de
#   TF_VAR_metrics_token, nunca de arquivo versionado.

data "azurerm_client_config" "atual" {}

locals {
  # Nome do Web App precisa ser único no mundo todo (vira <nome>.azurewebsites.net).
  sufixo   = substr(md5(data.azurerm_client_config.atual.subscription_id), 0, 6)
  nome_app = "${var.prefixo}-${local.sufixo}"
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefixo}"
  location = var.localizacao
  tags     = var.tags
}

resource "azurerm_service_plan" "plano" {
  name                = "asp-${var.prefixo}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = var.sku
  tags                = var.tags
}

resource "azurerm_linux_web_app" "app" {
  name                = local.nome_app
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  service_plan_id     = azurerm_service_plan.plano.id
  tags                = var.tags

  https_only                                     = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  site_config {
    # O plano F1 não permite "always on": o app dorme após ~20 min sem acesso.
    always_on                         = var.sku != "F1"
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    scm_minimum_tls_version           = "1.2"
    scm_ip_restriction_default_action = "Deny"

    application_stack {
      docker_registry_url = "https://ghcr.io"
      docker_image_name   = var.imagem
    }
  }

  app_settings = {
    WEBSITES_PORT                       = "8000"
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    AMBIENTE                            = "producao"
    DEMO_FALHAS                         = tostring(var.demo_falhas)
    METRICS_TOKEN                       = var.metrics_token
  }

  logs {
    detailed_error_messages = false
    failed_request_tracing  = false

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  lifecycle {
    # A tag da imagem é responsabilidade do pipeline (deploy contínuo), não do Terraform.
    ignore_changes = [site_config[0].application_stack]
  }
}
