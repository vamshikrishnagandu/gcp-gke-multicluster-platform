variable "project_id" {
  type = string
}

variable "regions" {
  description = "Cluster key -> region + CIDRs. The FIRST key (alphabetically) is the config cluster."
  type = map(object({
    region        = string
    nodes_cidr    = string
    pods_cidr     = string
    services_cidr = string
    master_cidr   = string
    ops_cidr      = string
    proxy_cidr    = string
  }))
  default = {
    usc1 = {
      region        = "us-central1"
      nodes_cidr    = "10.10.0.0/20"
      pods_cidr     = "10.20.0.0/16"
      services_cidr = "10.30.0.0/20"
      master_cidr   = "172.16.0.0/28"
      ops_cidr      = "10.12.0.0/24"
      proxy_cidr    = "10.14.0.0/23"
    }
    use1 = {
      region        = "us-east1"
      nodes_cidr    = "10.11.0.0/20"
      pods_cidr     = "10.21.0.0/16"
      services_cidr = "10.31.0.0/20"
      master_cidr   = "172.16.0.16/28"
      ops_cidr      = "10.13.0.0/24"
      proxy_cidr    = "10.15.0.0/23"
    }
  }
}

variable "apps" {
  type    = list(string)
  default = ["app1", "app2"]
}

variable "machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "spot_nodes" {
  description = "Cheaper Spot nodes for the personal-account demo. Set false for real production."
  type        = bool
  default     = true
}

variable "min_nodes_per_cluster" {
  type    = number
  default = 2
}

variable "max_nodes_per_cluster" {
  type    = number
  default = 6
}

variable "ci_apps_sa" {
  description = "From bootstrap output ci_apps_sa."
  type        = string
}

variable "deletion_protection" {
  description = "false makes `terraform destroy` possible (personal account / demo)."
  type        = bool
  default     = true
}

variable "enable_sql_replica" {
  type    = bool
  default = true
}

variable "enable_redis_dr_instance" {
  description = "Provision a billable cold-restore Redis instance in the secondary region; leave false until recovery is needed."
  type        = bool
  default     = false
}

variable "binauthz_enforcement_mode" {
  type    = string
  default = "ENFORCED_BLOCK_AND_AUDIT_LOG"
}

variable "uptime_host" {
  description = "Any non-empty value enables uptime checks; they probe the HTTPS gateway hostname (see output gateway_hostname)."
  type        = string
  default     = ""
}

variable "domain" {
  description = "Public hostname served by the Gateway. Empty = <ip-with-dashes>.nip.io (free wildcard DNS, no registrar needed)."
  type        = string
  default     = ""
}

variable "dns_zone_domain" {
  description = "DNS-zone apex you own (e.g. example.com). Set together with domain to create a Cloud DNS zone and the A record; then delegate the zone's nameservers at your registrar."
  type        = string
  default     = ""
}

variable "team_members" {
  description = "Role-based access: members (user:/group:/serviceAccount: prefixed) per team. See modules/iam."
  type = object({
    developers = optional(list(string), [])
    operators  = optional(list(string), [])
    sres       = optional(list(string), [])
  })
  default = {}
}

variable "alert_email" {
  type    = string
  default = ""
}

variable "grafana_principal" {
  type    = string
  default = ""
}

variable "labels" {
  type = map(string)
  default = {
    environment = "prod"
    managed-by  = "terraform"
  }
}
