variable "project_id" {
  type = string
}

variable "network_name" {
  type    = string
  default = "platform-vpc"
}

variable "subnets" {
  description = "Map of short name -> region and CIDRs. Per region: GKE nodes, ops/monitoring, and a proxy-only subnet for Envoy-based load balancers."
  type = map(object({
    region        = string
    nodes_cidr    = string
    pods_cidr     = string
    services_cidr = string
    ops_cidr      = string
    proxy_cidr    = string
  }))
}

variable "psa_cidr" {
  description = "Range reserved for Google-managed services (Cloud SQL, Memorystore)."
  type        = string
  default     = "10.100.0.0/16"
}
