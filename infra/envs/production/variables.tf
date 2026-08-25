variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "dr_region" {
  description = "Região secundária só para o bucket de backup do Velero (cross-region DR)"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  type    = string
  default = "solidarytech-eks"
}

variable "kubernetes_version" {
  # 1.29 foi descontinuado pela AWS (EKS só aceita 1.31+ no momento desta entrega, ver
  # `aws eks describe-cluster-versions`). Ajustar aqui se a AWS avançar o ciclo de suporte
  # de novo antes da apresentação.
  type    = string
  default = "1.31"
}

# --- AWS Academy: preencher com o ARN da LabRole da sua conta voclabs.
# Formato típico: arn:aws:iam::<account_id>:role/LabRole
# Em conta própria (fora da Academy), aponte para roles criadas normalmente via Terraform.
variable "lab_role_arn" {
  description = "ARN da IAM role pré-existente (LabRole) usada pelo EKS control plane e node groups"
  type        = string
}

variable "rds_master_username" {
  type    = string
  default = "solidarytech_admin"
}

variable "rds_master_password" {
  description = "Senha do master user do RDS. Passar via TF_VAR_rds_master_password (nunca commitar)."
  type        = string
  sensitive   = true
}

variable "gitops_repo_url" {
  description = "URL do repositório Git (mesmo monorepo ou repo gitops dedicado) lido pelo ArgoCD"
  type        = string
}

variable "gitops_target_revision" {
  type    = string
  default = "main"
}

variable "git_repo_token" {
  description = "PAT/token de leitura do repositório GitOps (necessário se o repo for privado). Passar via TF_VAR_git_repo_token, nunca commitar."
  type        = string
  default     = ""
  sensitive   = true
}

variable "velero_bucket_suffix" {
  description = "Sufixo único para o bucket de backup do Velero (ex: conta AWS ou RM do grupo)"
  type        = string
}

variable "datadog_api_key" {
  description = "API key do Datadog"
  type        = string
  default     = ""
  sensitive   = true
}

variable "datadog_site" {
  type    = string
  default = "datadoghq.com"
}


variable "enable_argocd_bootstrap" {
  description = "Desligar para o primeiro `apply` (cluster ainda não existe -> provider kubernetes/helm falhariam). Ligar depois que o EKS já estiver de pé."
  type        = bool
  default     = true
}
