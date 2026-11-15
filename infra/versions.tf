terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.40"
    }
  }

  # State remoto em Azure Storage, criptografado e com lock. A configuração (nome da
  # conta, container e chave) fica em backend.hcl, que está no .gitignore:
  #   terraform init -backend-config=backend.hcl
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  # subscription_id vem de ARM_SUBSCRIPTION_ID (variável de ambiente), nunca do código.

  # Não tenta registrar dezenas de provedores que não usamos (falhava com 409 em
  # Microsoft.HDInsight). Os necessários (Microsoft.Web, Microsoft.ManagedIdentity e
  # Microsoft.Storage) são registrados explicitamente por scripts/azure_setup.sh.
  resource_provider_registrations = "none"
}
