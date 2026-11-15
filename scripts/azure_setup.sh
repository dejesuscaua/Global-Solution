#!/usr/bin/env bash
# Configura toda a nuvem do SeguWatts em um comando.
#
# Rode no Azure Cloud Shell (Bash), que já tem az e terraform e já está logado:
#   1. Abra https://shell.azure.com e escolha Bash
#   2. git clone https://github.com/dejesuscaua/Global-Solution.git && cd Global-Solution
#   3. ./scripts/azure_setup.sh
#
# Também funciona no seu computador, depois de `az login`.
#
# Variáveis opcionais:
#   LOCALIZACAO=eastus2 ./scripts/azure_setup.sh   (se a sua assinatura não permitir brazilsouth)
#   SKU=B1 ./scripts/azure_setup.sh                (padrão F1, gratuito)
#   PREFIXO=seguwatts                              (nome base dos recursos)
#
# O script é idempotente: se algo falhar no meio, corrija e rode de novo.
set -euo pipefail

LOCALIZACAO="${LOCALIZACAO:-brazilsouth}"
PREFIXO="${PREFIXO:-seguwatts}"
SKU="${SKU:-F1}"
REPO_GITHUB="${REPO_GITHUB:-dejesuscaua/Global-Solution}"
IMAGEM="${IMAGEM:-dejesuscaua/global-solution:latest}"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
INFRA="$RAIZ/infra"

passo() { printf '\n\033[1;35m▶ %s\033[0m\n' "$*"; }
ok() { printf '  \033[32m✔\033[0m %s\n' "$*"; }
falha() { printf '\n\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

trap 'falha "Parou na linha $LINENO. Leia a mensagem acima; depois de corrigir, rode o script de novo."' ERR

passo "Conferindo ferramentas e login"
command -v az >/dev/null || falha "Azure CLI não encontrada. Use o Cloud Shell (shell.azure.com) ou instale a az."
command -v terraform >/dev/null || falha "Terraform não encontrado. Use o Cloud Shell ou instale o Terraform >= 1.6."
az account show >/dev/null 2>&1 || falha "Você não está logado. Rode: az login"
ASSINATURA_ID="$(az account show --query id -o tsv)"
ASSINATURA_NOME="$(az account show --query name -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
ok "Assinatura: $ASSINATURA_NOME ($ASSINATURA_ID)"
ok "Região: $LOCALIZACAO | Plano: $SKU | Prefixo: $PREFIXO"
ok "$(terraform version | head -1)"
export ARM_SUBSCRIPTION_ID="$ASSINATURA_ID"

if [[ "${CONFIRMAR:-sim}" == "sim" ]]; then
  read -r -p "  Criar os recursos nesta assinatura? [s/N] " resposta
  [[ "$resposta" =~ ^[sS]$ ]] || falha "Cancelado. Para outra assinatura: az account set --subscription <id>"
fi

passo "Registrando os provedores de recursos (só na primeira vez demora)"
for provedor in Microsoft.Web Microsoft.ManagedIdentity Microsoft.Storage; do
  estado="$(az provider show -n "$provedor" --query registrationState -o tsv 2>/dev/null || echo NotRegistered)"
  if [[ "$estado" != "Registered" ]]; then
    az provider register -n "$provedor" --wait -o none
  fi
  ok "$provedor"
done

passo "Storage para o state do Terraform (criptografado, sem acesso público)"
RG_STATE="rg-${PREFIXO}-tfstate"
# Nome global e único: prefixo + 6 caracteres derivados da assinatura.
SUFIXO="$(printf '%s' "$ASSINATURA_ID" | sha256sum | cut -c1-6)"
CONTA_STATE="st${PREFIXO}tf${SUFIXO}"
CONTA_STATE="${CONTA_STATE:0:24}"

if ! az group create -n "$RG_STATE" -l "$LOCALIZACAO" --tags projeto=seguwatts finalidade=tfstate -o none 2>/tmp/erro_rg; then
  if grep -q "RequestDisallowedByAzure\|disallowed\|not allowed" /tmp/erro_rg; then
    cat /tmp/erro_rg >&2
    falha "Sua assinatura não permite a região $LOCALIZACAO. Rode de novo com outra, ex.: LOCALIZACAO=eastus2 ./scripts/azure_setup.sh"
  fi
  cat /tmp/erro_rg >&2; false
fi
ok "Resource group $RG_STATE"

if ! az storage account show -n "$CONTA_STATE" -g "$RG_STATE" -o none 2>/dev/null; then
  az storage account create -n "$CONTA_STATE" -g "$RG_STATE" -l "$LOCALIZACAO" \
    --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
    --allow-blob-public-access false --https-only true -o none
fi
ok "Storage account $CONTA_STATE"

CHAVE="$(az storage account keys list -n "$CONTA_STATE" -g "$RG_STATE" --query '[0].value' -o tsv)"
az storage container create -n tfstate --account-name "$CONTA_STATE" --account-key "$CHAVE" -o none
unset CHAVE
ok "Container tfstate"

passo "Arquivos locais do Terraform (ficam fora do git)"
cat >"$INFRA/backend.hcl" <<EOF
resource_group_name  = "$RG_STATE"
storage_account_name = "$CONTA_STATE"
container_name       = "tfstate"
key                  = "vitrine.tfstate"
EOF
ok "infra/backend.hcl"

cat >"$INFRA/terraform.tfvars" <<EOF
prefixo            = "$PREFIXO"
localizacao        = "$LOCALIZACAO"
sku                = "$SKU"
imagem             = "$IMAGEM"
github_repositorio = "$REPO_GITHUB"
demo_falhas        = false
EOF
ok "infra/terraform.tfvars"

ARQ_TOKEN="$INFRA/.metrics_token"
if [[ ! -s "$ARQ_TOKEN" ]]; then
  (umask 077 && openssl rand -hex 24 >"$ARQ_TOKEN")
  ok "Token de métricas gerado em infra/.metrics_token"
else
  ok "Reaproveitando o token de métricas existente"
fi
TF_VAR_metrics_token="$(cat "$ARQ_TOKEN")"
export TF_VAR_metrics_token

passo "terraform init"
terraform -chdir="$INFRA" init -input=false -reconfigure -backend-config=backend.hcl

passo "terraform plan"
terraform -chdir="$INFRA" plan -input=false -out=plano.tfplan

passo "terraform apply"
terraform -chdir="$INFRA" apply -input=false plano.tfplan
rm -f "$INFRA/plano.tfplan"

saida() { terraform -chdir="$INFRA" output -raw "$1"; }
URL="$(saida url_publica)"

passo "Conferindo a aplicação no ar"
no_ar=nao
# No F1 o primeiro start baixa a imagem e sobe o container: pode levar alguns minutos.
for _ in $(seq 1 30); do
  if curl -fsS "$URL/healthz" >/dev/null 2>&1; then
    ok "$URL/healthz respondeu"
    no_ar=sim
    break
  fi
  sleep 10
done
if [[ "$no_ar" == "nao" ]]; then
  printf '  \033[33m!\033[0m %s\n' "$URL ainda não respondeu em 5 min. Veja os logs: az webapp log tail -n $(saida web_app) -g $(saida resource_group)"
fi

passo "Configurando o deploy automático no GitHub"
VARIAVEIS=(
  "AZURE_CLIENT_ID=$(saida azure_client_id)"
  "AZURE_TENANT_ID=$TENANT_ID"
  "AZURE_SUBSCRIPTION_ID=$ASSINATURA_ID"
  "AZURE_RESOURCE_GROUP=$(saida resource_group)"
  "AZURE_WEBAPP_NAME=$(saida web_app)"
  "DEPLOY_HABILITADO=true"
)
github_ok=nao
if command -v gh >/dev/null; then
  if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    echo "  Para criar as variables do GitHub automaticamente, faça login uma vez."
    echo "  Vai aparecer um código: abra https://github.com/login/device e cole o código."
    gh auth login --hostname github.com --git-protocol https --web --scopes repo,workflow || true
  fi
  if gh auth status --hostname github.com >/dev/null 2>&1; then
    for par in "${VARIAVEIS[@]}"; do
      gh variable set "${par%%=*}" --repo "$REPO_GITHUB" --body "${par#*=}"
      ok "${par%%=*}"
    done
    github_ok=sim
    if gh workflow run devsecops.yml --repo "$REPO_GITHUB" --ref main 2>/dev/null; then
      ok "Primeiro deploy disparado: https://github.com/$REPO_GITHUB/actions"
    fi
  fi
fi

if [[ "$github_ok" == "nao" ]]; then
  echo
  echo "  Não consegui usar o GitHub CLI. Crie estas VARIABLES em"
  echo "  https://github.com/$REPO_GITHUB/settings/variables/actions (nenhuma é segredo):"
  echo
  for par in "${VARIAVEIS[@]}"; do
    printf '    %-24s %s\n' "${par%%=*}" "${par#*=}"
  done
fi

passo "Pronto!"
cat <<EOF

  URL pública do MVP:  $URL
  (no plano F1 o app dorme após ~20 min sem acesso; o primeiro acesso leva uns 30 s)

  Deploy sem senha: o GitHub usa OIDC com a identidade $(saida azure_client_id)
  Daqui para frente, qualquer push na main publica sozinho.

  Para o Prometheus local ler o /metrics de produção:
    host:  $(saida fqdn)
    token: $(cat "$ARQ_TOKEN")
    (guarde o token: a sessão do Cloud Shell pode ser apagada; ele vai em
     observability/prometheus/metrics_token no seu computador)
EOF
