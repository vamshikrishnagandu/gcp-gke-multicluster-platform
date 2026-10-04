variable "project_id" {
  type = string
}

variable "network_id" {
  type = string
}

variable "primary_region" {
  type = string
}

variable "secondary_region" {
  type = string
}

variable "name_suffix" {
  description = "Cloud SQL names are reserved for ~1 week after deletion; bump this to re-create quickly."
  type        = string
  default     = "v1"
}

variable "sql_tier" {
  type    = string
  default = "db-custom-1-3840"
}

variable "sql_database_version" {
  type    = string
  default = "POSTGRES_16"
}

variable "enable_sql_replica" {
  description = "Cross-region read replica (DR). Doubles SQL cost."
  type        = bool
  default     = true
}

variable "redis_memory_gb" {
  type    = number
  default = 1
}

variable "enable_redis_dr_instance" {
  description = "Create a billable secondary Redis instance in secondary_region for cold-restore testing or regional recovery."
  type        = bool
  default     = false
}

variable "firestore_location" {
  description = "Multi-region location for Firestore (nam5 = US multi-region, eur3 = EU)."
  type        = string
  default     = "nam5"
}

variable "app_names" {
  type = list(string)
}

variable "app_service_accounts" {
  description = "app -> GSA email; used for IAM database authentication users."
  type        = map(string)
}

variable "secret_replica_regions" {
  type = list(string)
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "redis_app" {
  description = "The app that reads the Redis auth string and CA certificate secrets."
  type        = string
  default     = "app2"
}
