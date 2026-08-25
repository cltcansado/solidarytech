variable "cluster_id" {
  type    = string
  default = "solidarytech-cache"
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "allowed_security_group_ids" {
  type = list(string)
}

variable "node_type" {
  description = "cache.t3.micro é suficiente para cache leve; rever após medir hit ratio real"
  type        = string
  default     = "cache.t3.micro"
}

variable "tags" {
  type    = map(string)
  default = {}
}
