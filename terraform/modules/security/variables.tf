variable "project_id" {
  type = string
}

variable "apps" {
  description = "Application names. Each gets a GSA bound to KSA <app>/<app> via Workload Identity."
  type        = list(string)
}

variable "app_roles" {
  description = "Project roles granted to every application GSA."
  type        = list(string)
  default = [
    "roles/cloudtrace.agent",
    "roles/cloudprofiler.agent",
    "roles/errorreporting.writer",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/cloudsql.client",
    "roles/datastore.user",
  ]
}

variable "secret_replica_regions" {
  description = "Secrets are replicated to exactly these regions (data residency + regional failure)."
  type        = list(string)
}

variable "kms_location" {
  type    = string
  default = "global"
}

variable "kms_keyring_name" {
  description = "KMS key rings can NEVER be deleted. Change the suffix if you destroy and re-create the project resources."
  type        = string
  default     = "binauthz-v1"
}

variable "binauthz_enforcement_mode" {
  description = "ENFORCED_BLOCK_AND_AUDIT_LOG or DRYRUN_AUDIT_LOG_ONLY (log only - useful while rolling out)."
  type        = string
  default     = "ENFORCED_BLOCK_AND_AUDIT_LOG"

  validation {
    condition     = contains(["ENFORCED_BLOCK_AND_AUDIT_LOG", "DRYRUN_AUDIT_LOG_ONLY"], var.binauthz_enforcement_mode)
    error_message = "Use ENFORCED_BLOCK_AND_AUDIT_LOG or DRYRUN_AUDIT_LOG_ONLY."
  }
}

variable "ci_apps_sa" {
  description = "CI service account that signs attestations (needs signer on the key)."
  type        = string
}

variable "rate_limit_requests_per_minute" {
  type    = number
  default = 600
}
