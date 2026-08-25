variable "name_prefix" {
  type    = string
  default = "solidarytech"
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "azs" {
  description = "Availability Zones (2, mínimo exigido pelo EKS)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.42.0.0/20", "10.42.16.0/20"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.42.128.0/20", "10.42.144.0/20"]
}

variable "single_nat_gateway" {
  description = "Usa 1 NAT Gateway só (em vez de 1 por AZ) — economia FinOps para ambiente de estudo/hackathon"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Usado para tagar subnets com kubernetes.io/cluster/<name>=shared (obrigatório para o ALB/NLB controller e para o EKS enxergar as subnets)"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
