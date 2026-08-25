variable "table_name" {
  type    = string
  default = "SolidaryTechVolunteers"
}

variable "hash_key" {
  type    = string
  default = "volunteer_id"
}

variable "tags" {
  type    = map(string)
  default = {}
}
