variable "namespace" {
  type    = string
  default = "argocd"
}

variable "chart_version" {
  description = "Versão do chart argo-cd (https://artifacthub.io/packages/helm/argo/argo-cd)"
  type        = string
  default     = "7.3.11"
}

variable "gitops_repo_url" {
  description = "URL do repositório Git que contém gitops/ (pode ser o mesmo monorepo)"
  type        = string
}

variable "gitops_root_path" {
  description = "Caminho dentro do repo onde está o app-of-apps raiz"
  type        = string
  default     = "gitops/argocd"
}

variable "target_revision" {
  type    = string
  default = "main"
}

variable "git_repo_token" {
  description = "PAT/token com escopo de leitura no repositório GitOps (repo privado). Vazio = sem credencial registrada (só funciona se o repo for público). Passar via TF_VAR_git_repo_token, nunca commitar."
  type        = string
  default     = ""
  sensitive   = true
}

variable "git_repo_username" {
  description = "Usuário associado ao token acima (qualquer valor não-vazio funciona para auth via PAT do GitHub sobre HTTPS)"
  type        = string
  default     = "git"
}
