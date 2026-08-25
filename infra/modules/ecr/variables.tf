variable "repository_names" {
  type    = list(string)
  default = ["ngo-service", "donation-service", "volunteer-service", "healer-service"]
}

variable "keep_last_n_images" {
  description = "Lifecycle policy: mantém só as N imagens mais recentes por repo (custo de storage ECR — FinOps)"
  type        = number
  default     = 10
}

variable "tags" {
  type    = map(string)
  default = {}
}
