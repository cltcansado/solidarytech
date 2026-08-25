variable "cluster_name" {
  type    = string
  default = "solidarytech-eks"
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "vpc_id" {
  type = string
}

# EKS control plane precisa enxergar subnets públicas (ALB/NLB) e privadas (nós).
variable "subnet_ids" {
  type = list(string)
}

variable "node_subnet_ids" {
  description = "Subnets onde os node groups sobem (normalmente as privadas)"
  type        = list(string)
}

# --- AWS Academy (voclabs): não é possível criar roles/policies IAM novas
# (iam:CreateRole é negado). O padrão é usar a role pré-existente `LabRole`, tanto para o
# control plane do EKS quanto para os node groups. Em conta própria (não-Academy), troque
# estes ARNs por roles criadas via Terraform normalmente (aws_iam_role + policy attachments).
variable "cluster_role_arn" {
  description = "ARN da IAM role usada pelo control plane do EKS (LabRole na AWS Academy)"
  type        = string
}

variable "node_role_arn" {
  description = "ARN da IAM role usada pelos node groups (LabRole na AWS Academy)"
  type        = string
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "spot_node_instance_types" {
  description = "Node group Spot para cargas não-críticas (ngo-service/volunteer-service) — recomendação FinOps"
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "enable_spot_node_group" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
