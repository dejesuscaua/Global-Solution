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
  description = "Imagem inicial do container. Depois do primeiro apply, o pipeline troca a tag a cada deploy."
  type        = string
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

variable "github_repositorio" {
  description = "Repositório (dono/nome, com maiúsculas exatas) autorizado a fazer deploy via OIDC."
  type        = string
  default     = "dejesuscaua/Global-Solution"
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
