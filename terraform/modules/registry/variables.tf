variable "project_id" {
  type = string
}

variable "location" {
  description = "Multi-region (us, europe, asia) for durability across regional outages."
  type        = string
  default     = "us"
}

variable "repository_id" {
  type    = string
  default = "apps"
}

variable "cleanup_dry_run" {
  type    = bool
  default = false
}

variable "labels" {
  type    = map(string)
  default = {}
}
