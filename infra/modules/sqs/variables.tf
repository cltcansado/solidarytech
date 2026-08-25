variable "queue_name" {
  type    = string
  default = "solidary-donations"
}

variable "max_receive_count" {
  description = "Tentativas antes de mover a mensagem para a DLQ"
  type        = number
  default     = 3
}

variable "visibility_timeout_seconds" {
  type    = number
  default = 30
}

variable "message_retention_seconds" {
  type    = number
  default = 1209600 # 14 dias
}

variable "tags" {
  type    = map(string)
  default = {}
}
