output "network_id" {
  value = google_compute_network.vpc.id
}

output "network_name" {
  value = google_compute_network.vpc.name
}

output "network_self_link" {
  value = google_compute_network.vpc.self_link
}

output "subnets" {
  value = { for k, s in google_compute_subnetwork.subnet : k => {
    name      = s.name
    self_link = s.self_link
    region    = s.region
  } }
}

output "psa_connection" {
  description = "Depend on this before creating Cloud SQL / Redis private IP instances."
  value       = google_service_networking_connection.psa.id
}
