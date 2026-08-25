variable "project" {
  type    = string
  default = "SolidaryTech"
}

variable "environment" {
  type    = string
  default = "Production"
}

variable "cost_center" {
  type    = string
  default = "NGO-Core"
}

variable "extra_tags" {
  description = "Tags adicionais específicas do recurso/módulo (ex: Component=donation-service)"
  type        = map(string)
  default     = {}
}
