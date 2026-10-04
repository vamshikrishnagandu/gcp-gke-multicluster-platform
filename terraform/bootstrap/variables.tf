variable "project_id" {
  description = "Globally unique ID for the NEW project (6-30 chars, lowercase, digits, hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 chars: lowercase letters, digits, hyphens; start with a letter."
  }
}

variable "project_name" {
  description = "Human-friendly display name."
  type        = string
  default     = "GKE Multi-Cluster Platform"
}

variable "billing_account" {
  description = "Billing account ID (XXXXXX-XXXXXX-XXXXXX) from `gcloud billing accounts list`."
  type        = string
}

variable "org_id" {
  description = "Organization ID. Leave empty for a personal (no-organization) account."
  type        = string
  default     = ""
}

variable "folder_id" {
  description = "Folder ID (optional, mutually exclusive with org_id)."
  type        = string
  default     = ""
}

variable "region" {
  description = "Default region for regional resources created here."
  type        = string
  default     = "us-central1"
}

variable "state_bucket_location" {
  description = "Location of the Terraform state bucket (multi-region survives a regional outage)."
  type        = string
  default     = "US"
}

variable "github_repository" {
  description = "GitHub repo allowed to impersonate the CI service accounts, as owner/name."
  type        = string
  default     = "vamshikrishnagandu/gcp-gke-multicluster-platform"
}

variable "github_repository_id" {
  description = "Immutable numeric ID of the GitHub repository allowed to impersonate CI service accounts."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be a numeric GitHub repository ID."
  }
}

variable "github_repository_owner_id" {
  description = "Immutable numeric ID of the GitHub user or organization that owns the repository."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_owner_id))
    error_message = "github_repository_owner_id must be a numeric GitHub owner ID."
  }
}

variable "budget_amount" {
  description = "Monthly budget used for alert e-mails (does NOT cap spend)."
  type        = number
  default     = 150
}

variable "budget_currency" {
  description = "Must equal the billing account currency (USD, GBP, INR, EUR...)."
  type        = string
  default     = "USD"
}

variable "project_deletion_policy" {
  description = "PREVENT blocks `terraform destroy` from deleting the project. Set DELETE when tearing down."
  type        = string
  default     = "PREVENT"
}

variable "labels" {
  description = "Labels applied to the project (cost reporting)."
  type        = map(string)
  default = {
    owner       = "platform-team"
    environment = "prod"
    managed-by  = "terraform"
  }
}
