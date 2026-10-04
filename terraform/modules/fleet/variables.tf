variable "project_id" {
  type = string
}

variable "config_membership" {
  description = "Fleet membership of the config cluster (holds Gateway/HTTPRoute objects)."
  type        = string
}

variable "workload_pool" {
  type = string
}

variable "memberships" {
  description = "Cluster Fleet memberships to enroll in managed Cloud Service Mesh."
  type = map(object({
    id       = string
    location = string
  }))
}
