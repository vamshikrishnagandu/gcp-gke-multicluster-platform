variable "project_id" {
  type = string
}

variable "config_membership" {
  description = "Fleet membership of the config cluster (holds Gateway/HTTPRoute objects)."
  type        = string
}
