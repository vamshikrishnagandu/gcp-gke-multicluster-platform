variable "project_id" {
  type = string
}

variable "developers" {
  description = "Members (user:, group:, serviceAccount:) with read-only developer access."
  type        = list(string)
  default     = []
}

variable "operators" {
  description = "Members who operate the clusters and registry."
  type        = list(string)
  default     = []
}

variable "sres" {
  description = "Members who own monitoring, alerting and incident response."
  type        = list(string)
  default     = []
}
