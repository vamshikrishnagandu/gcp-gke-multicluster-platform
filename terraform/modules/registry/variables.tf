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

variable "backup_location" {
  description = "Region for the independent image recovery repository."
  type        = string
  default     = "us-east1"
}

variable "backup_repository_id" {
  type    = string
  default = "apps-backup"
}

variable "cleanup_dry_run" {
  type    = bool
  default = false
}

variable "labels" {
  type    = map(string)
  default = {}
}
