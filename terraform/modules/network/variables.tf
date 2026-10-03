variable "project_id" {
  type = string
}

variable "network_name" {
  type    = string
  default = "platform-vpc"
}

variable "subnets" {
  description = "Map of short name -> region and CIDRs. One subnet per GKE cluster region."
  type = map(object({
    region        = string
    nodes_cidr    = string
    pods_cidr     = string
    services_cidr = string
  }))
}

variable "psa_cidr" {
  description = "Range reserved for Google-managed services (Cloud SQL, Memorystore)."
  type        = string
  default     = "10.100.0.0/16"
}
