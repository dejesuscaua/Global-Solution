# Infraestrutura da vitrine SeguWatts no Azure Container Apps.
#
# Decisões de segurança:
# - Não existe VM, SSH, RDP nem porta de administração: o único ponto de entrada é o
#   ingress HTTPS gerenciado (443). HTTP puro é recusado (allow_insecure_connections = false).
# - O token de métricas é um secret do Container App, injetado como variável de ambiente.
# - Logs vão para um Log Analytics com cota diária, para o custo não fugir do controle.

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefixo}"
  location = var.localizacao
  tags     = var.tags
}

resource "azurerm_log_analytics_workspace" "logs" {
  name                = "log-${var.prefixo}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 0.5
  tags                = var.tags
}

resource "azurerm_container_app_environment" "env" {
  name                       = "cae-${var.prefixo}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id
  tags                       = var.tags
}

resource "azurerm_container_app" "app" {
  name                         = "${var.prefixo}-app"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"
  tags                         = var.tags

  secret {
    name  = "metrics-token"
    value = var.metrics_token
  }

  ingress {
    external_enabled           = true
    target_port                = 8000
    transport                  = "auto"
    allow_insecure_connections = false

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    # Uma réplica fixa: sem cold start na correção e métricas consistentes no Prometheus.
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "vitrine"
      image  = var.imagem
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "AMBIENTE"
        value = "producao"
      }

      env {
        name        = "METRICS_TOKEN"
        secret_name = "metrics-token"
      }

      env {
        name  = "DEMO_FALHAS"
        value = tostring(var.demo_falhas)
      }

      liveness_probe {
        transport = "HTTP"
        port      = 8000
        path      = "/healthz"
      }

      readiness_probe {
        transport = "HTTP"
        port      = 8000
        path      = "/healthz"
      }
    }
  }

  lifecycle {
    # A tag da imagem é responsabilidade do pipeline (deploy contínuo), não do Terraform.
    ignore_changes = [template[0].container[0].image]
  }
}
