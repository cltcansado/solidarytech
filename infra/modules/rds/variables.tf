variable "identifier" {
  type    = string
  default = "solidarytech-postgres"
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets privadas para o DB Subnet Group"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups que podem alcançar a porta 5432 (ex: SG dos nós do EKS)"
  type        = list(string)
}

variable "instance_class" {
  description = "Rightsizing inicial: t3.micro cobre a carga de hackathon/homologação com folga; revisar após 1 semana de métricas reais (ver docs/FINOPS-FORECAST.md)"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "engine_version" {
  # 16.3 saiu de disponibilidade no RDS (ver `aws rds describe-db-engine-versions --engine
  # postgres`) — ajustado para a patch mais recente da mesma minor version disponível no
  # momento desta entrega.
  type    = string
  default = "16.15"
}

variable "multi_az" {
  description = "Multi-AZ aumenta RTO/RPO de failover automático, mas dobra o custo do RDS — desligado por padrão no hackathon (custo), ligar em produção real (ver PCN)"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "master_username" {
  type    = string
  default = "solidarytech_admin"
}

variable "master_password" {
  description = "Senha do master user. Em produção real, usar Secrets Manager; na Academy (sem IAM custom p/ rotação), passar via TF_VAR_master_password e nunca commitar."
  type        = string
  sensitive   = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
