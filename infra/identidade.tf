# Identidade do pipeline de deploy, sem senha.
#
# O GitHub Actions troca um token OIDC de curta duração (emitido para o job de deploy
# do environment "producao" deste repositório) por um token do Azure. Não existe
# client secret para vazar ou expirar, e a identidade só tem permissão neste
# resource group.
#
# Usa identidade gerenciada (e não app registration) porque contas Azure for Students
# normalmente não podem criar aplicativos no Entra ID do tenant da faculdade.

resource "azurerm_user_assigned_identity" "deploy" {
  name                = "id-${var.prefixo}-deploy"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

# Só o job que roda no environment "producao" deste repositório pode usar a identidade.
#
# O GitHub emite o "subject" do token em dois formatos, conforme a configuração do
# repositório, e cadastramos os dois:
#   imutável: repo:dono@<id do dono>/repo@<id do repo>:environment:producao
#             (padrão em repositórios novos; os IDs impedem que alguém recrie um repo
#             com o mesmo nome e herde o acesso)
#   clássico: repo:dono/repo:environment:producao
resource "azurerm_federated_identity_credential" "github_producao" {
  name      = "github-${var.prefixo}-producao"
  parent_id = azurerm_user_assigned_identity.deploy.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${var.github_dono}@${var.github_dono_id}/${var.github_repo_nome}@${var.github_repo_id}:environment:producao"
}

resource "azurerm_federated_identity_credential" "github_producao_classico" {
  name      = "github-${var.prefixo}-producao-classico"
  parent_id = azurerm_user_assigned_identity.deploy.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${var.github_dono}/${var.github_repo_nome}:environment:producao"
}

# Contributor apenas no resource group da aplicação: o pipeline consegue atualizar o
# Web App, mas não enxerga nem altera nada fora dele.
resource "azurerm_role_assignment" "deploy_rg" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.deploy.principal_id
  principal_type       = "ServicePrincipal"
}
