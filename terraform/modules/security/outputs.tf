output "app_service_accounts" {
  description = "app name -> GSA email (annotate the KSA with this)."
  value       = { for k, sa in google_service_account.app : k => sa.email }
}

output "security_policy_name" {
  value = google_compute_security_policy.edge.name
}

output "attestor" {
  value = google_binary_authorization_attestor.build.name
}

output "attestor_key_version" {
  description = "KMS key version used by CI to sign attestations."
  value       = data.google_kms_crypto_key_version.attestor.name
}
