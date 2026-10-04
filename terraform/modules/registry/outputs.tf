output "repository_url" {
  description = "Prefix for image names, e.g. us-docker.pkg.dev/PROJECT/apps"
  value       = "${google_artifact_registry_repository.docker.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}

output "repository_id" {
  value = google_artifact_registry_repository.docker.repository_id
}

output "backup_repository_url" {
  value = "${google_artifact_registry_repository.backup.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.backup.repository_id}"
}
