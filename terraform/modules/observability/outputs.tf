output "bq_dataset" {
  value = google_bigquery_dataset.logs.dataset_id
}

output "usage_dataset" {
  value = google_bigquery_dataset.gke_usage.dataset_id
}

output "grafana_service_account" {
  value = google_service_account.grafana.email
}

output "grafana_auth_service_account" {
  value = google_service_account.grafana_auth.email
}

output "sinks" {
  value = { for k, s in google_logging_project_sink.bq : k => s.name }
}
