output "name" {
  value = google_container_cluster.this.name
}

output "location" {
  value = google_container_cluster.this.location
}

output "id" {
  value = google_container_cluster.this.id
}

output "membership" {
  description = "Fleet membership path: projects/P/locations/L/memberships/M."
  value       = "projects/${var.project_id}/locations/${google_container_cluster.this.fleet[0].membership_location}/memberships/${google_container_cluster.this.fleet[0].membership_id}"
}

output "dns_endpoint" {
  value = google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint
}

output "node_service_account" {
  value = google_service_account.nodes.email
}
