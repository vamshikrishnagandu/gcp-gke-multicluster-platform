variable "project_id" {
  type = string
}

variable "name" {
  description = "Cluster name, e.g. gke-usc1."
  type        = string
}

variable "region" {
  description = "Regional cluster = control plane + nodes replicated across 3 zones."
  type        = string
}

variable "network" {
  type = string
}

variable "subnetwork" {
  type = string
}

variable "master_cidr" {
  description = "/28 for the Google-managed control plane (private cluster)."
  type        = string
}

variable "master_authorized_cidrs" {
  description = "Extra CIDRs allowed to the public IP endpoint. Prefer the DNS endpoint (IAM-protected) instead."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "release_channel" {
  type    = string
  default = "REGULAR"
}

variable "machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "spot" {
  description = "Spot VMs are ~60-90% cheaper but can be reclaimed. OK for a demo, not for real prod."
  type        = bool
  default     = false
}

variable "node_locations" {
  description = "Zones for nodes. Empty = all zones of the region (usually 3)."
  type        = list(string)
  default     = []
}

variable "min_nodes" {
  description = "Total minimum nodes across all zones."
  type        = number
  default     = 2
}

variable "max_nodes" {
  description = "Total maximum nodes across all zones."
  type        = number
  default     = 6
}

variable "backup_namespaces" {
  description = "Namespaces protected by Backup for GKE."
  type        = list(string)
  default     = ["app1", "app2"]
}

variable "backup_retain_days" {
  type    = number
  default = 14
}

variable "usage_export_dataset" {
  description = "BigQuery dataset ID for GKE usage metering. Empty = disabled."
  type        = string
  default     = ""
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "labels" {
  type    = map(string)
  default = {}
}
