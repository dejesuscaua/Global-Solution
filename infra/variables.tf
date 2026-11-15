variable "prefixo" {
  description = "Prefixo dos recursos (letras minúsculas e números)."
  type        = string
  default     = "seguwatts"

  validation {
    condition     = can(regex("^[a-z0-9]{3,16}$", var.prefixo))
    error_message = "Use de 3 a 16 letras minúsculas ou números."
  }
}

variable "localizacao" {
  description = "Região do Azure. Brazil South deixa os dados e a latência no Brasil."
  type        = string
  default     = "brazilsouth"
}

variable "imagem" {
  description = "Imagem inicial no GHCR (sem o host). Depois do primeiro apply, o pipeline troca a tag a cada deploy."
  type        = string
  default     = "dejesuscaua/global-solution:latest"
}

variable "sku" {
  description = "Plano do App Service. F1 é gratuito (60 min de CPU por dia, sem always on); B1 é o menor pago."
  type        = string
  default     = "F1"

  validation {
    condition     = contains(["F1", "B1", "B2", "S1"], var.sku)
    error_message = "Use F1 (gratuito), B1, B2 ou S1."
  }
}

variable "metrics_token" {
  description = "Token Bearer exigido em /metrics. Informe via TF_VAR_metrics_token, nunca em arquivo versionado."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.metrics_token) >= 24
    error_message = "Use um token aleatório com pelo menos 24 caracteres (ex.: openssl rand -hex 24)."
  }
}

variable "demo_falhas" {
  description = "Liga a rota /api/demo/falha para demonstrar o alerta de erros. Deixe false fora da demonstração."
  type        = bool
  default     = false
}

# Repositório autorizado a fazer deploy via OIDC. Os IDs numéricos aparecem no log do
# azure/login ("subject claim") e em https://api.github.com/repos/<dono>/<repo>.
variable "github_dono" {
  description = "Dono do repositório no GitHub, com maiúsculas exatas."
  type        = string
  default     = "dejesuscaua"
}

variable "github_dono_id" {
  description = "ID numérico do dono no GitHub."
  type        = string
  default     = "84869963"
}

variable "github_repo_nome" {
  description = "Nome do repositório, com maiúsculas exatas."
  type        = string
  default     = "Global-Solution"
}

variable "github_repo_id" {
  description = "ID numérico do repositório no GitHub."
  type        = string
  default     = "1459249630"
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos."
  type        = map(string)
  default = {
    projeto    = "seguwatts"
    disciplina = "secure-devops"
    gs         = "2026.2"
    gerenciado = "terraform"
  }
}
