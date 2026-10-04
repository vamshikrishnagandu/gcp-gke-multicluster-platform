output "clusters" {
  value = { for k, c in module.gke : k => {
    name         = c.name
    location     = c.location
    dns_endpoint = c.dns_endpoint
  } }
}

output "config_cluster" {
  value = module.gke[local.config_key].name
}

output "gateway_ip" {
  value = google_compute_global_address.gateway.address
}

output "gateway_ip_name" {
  value = google_compute_global_address.gateway.name
}

output "registry" {
  value = module.registry.repository_url
}

output "backup_registry" {
  value = module.registry.backup_repository_url
}

output "app_service_accounts" {
  value = module.security.app_service_accounts
}

output "security_policy" {
  value = module.security.security_policy_name
}

output "attestor" {
  value = module.security.attestor
}

output "attestor_key_version" {
  value = module.security.attestor_key_version
}

output "sql_connection_name" {
  value = module.data.sql_connection_name
}

output "redis_host" {
  value = module.data.redis_host
}

output "redis_dr_backup_bucket" {
  value = module.data.redis_dr_backup_bucket
}

output "redis_dr_host" {
  value = module.data.redis_dr_host
}

output "bq_dataset" {
  value = module.observability.bq_dataset
}

output "grafana_service_account" {
  value = module.observability.grafana_service_account
}

output "grafana_auth_service_account" {
  value = module.observability.grafana_auth_service_account
}

output "get_credentials_commands" {
  value = [for k, c in module.gke : "gcloud container clusters get-credentials ${c.name} --region ${c.location} --project ${var.project_id} --dns-endpoint"]
}
