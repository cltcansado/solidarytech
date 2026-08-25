variable "bucket_name" {
  type = string
}

variable "lifecycle_expiration_days" {
  description = "Retenção dos backups Velero — equilíbrio entre RPO exigido no PCN e custo de S3"
  type        = number
  default     = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
