output "project_id" {
  value = google_project.this.project_id
}

output "project_number" {
  value = google_project.this.number
}

output "state_bucket" {
  value = google_storage_bucket.tfstate.name
}

output "wif_provider" {
  description = "Full provider resource name for google-github-actions/auth."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "ci_terraform_sa" {
  value = google_service_account.ci_terraform.email
}

output "ci_apps_sa" {
  value = google_service_account.ci_apps.email
}

output "gh_variable_commands" {
  description = "Copy/paste to configure GitHub Actions repository variables."
  value       = <<-EOT
    gh variable set GCP_PROJECT_ID   --body "${google_project.this.project_id}"
    gh variable set GCP_WIF_PROVIDER --body "${google_iam_workload_identity_pool_provider.github.name}"
    gh variable set GCP_TF_SA        --body "${google_service_account.ci_terraform.email}"
    gh variable set GCP_APPS_SA      --body "${google_service_account.ci_apps.email}"
    gh variable set TF_STATE_BUCKET  --body "${google_storage_bucket.tfstate.name}"
  EOT
}
