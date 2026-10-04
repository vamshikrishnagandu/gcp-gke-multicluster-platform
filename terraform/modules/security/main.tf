# -----------------------------------------------------------------------------
# Security module
#   1. Workload Identity: one Google SA per app, bound to its Kubernetes SA
#   2. Secret Manager: secrets with user-managed (2-region) replication
#   3. Cloud Armor: WAF (OWASP CRS) + rate limiting + Adaptive Protection
#   4. Binary Authorization: only KMS-signed images from our registry run
# -----------------------------------------------------------------------------

# ---------------------------------------------------------------- 1. Workload Identity
resource "google_service_account" "app" {
  for_each = toset(var.apps)

  project      = var.project_id
  account_id   = "wl-${each.key}"
  display_name = "Workload identity for ${each.key}"
}

locals {
  app_role_pairs = { for p in setproduct(var.apps, var.app_roles) : "${p[0]}|${p[1]}" => { app = p[0], role = p[1] } }
}

resource "google_project_iam_member" "app" {
  for_each = local.app_role_pairs

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.app[each.value.app].email}"
}

# ---------------------------------------------------------------- 2. Secret Manager
resource "google_secret_manager_secret" "app_api_key" {
  for_each = toset(var.apps)

  project   = var.project_id
  secret_id = "${each.key}-api-key"

  replication {
    user_managed {
      dynamic "replicas" {
        for_each = var.secret_replica_regions
        content {
          location = replicas.value
        }
      }
    }
  }
}

resource "random_password" "api_key" {
  for_each = toset(var.apps)
  length   = 40
  special  = false
}

resource "google_secret_manager_secret_version" "app_api_key" {
  for_each = toset(var.apps)

  secret      = google_secret_manager_secret.app_api_key[each.key].id
  secret_data = random_password.api_key[each.key].result
}

# Per-secret IAM (not project-wide): app1 cannot read app2's secrets.
resource "google_secret_manager_secret_iam_member" "app_api_key" {
  for_each = toset(var.apps)

  project   = var.project_id
  secret_id = google_secret_manager_secret.app_api_key[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app[each.key].email}"
}

# ---------------------------------------------------------------- 3. Cloud Armor
resource "google_compute_security_policy" "edge" {
  project     = var.project_id
  name        = "edge-waf"
  description = "WAF + rate limiting for the global Gateway"
  type        = "CLOUD_ARMOR"

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }

  advanced_options_config {
    log_level    = "VERBOSE" # which WAF rule matched is written to LB logs
    json_parsing = "STANDARD"
  }

  # --- OWASP Top-10 preconfigured rules (ModSecurity CRS 3.3) ---
  dynamic "rule" {
    for_each = {
      1000 = "sqli-v33-stable"
      1001 = "xss-v33-stable"
      1002 = "lfi-v33-stable"
      1003 = "rfi-v33-stable"
      1004 = "rce-v33-stable"
      1005 = "scannerdetection-v33-stable"
      1006 = "protocolattack-v33-stable"
      1007 = "sessionfixation-v33-stable"
    }
    content {
      priority    = rule.key
      action      = "deny(403)"
      description = "OWASP CRS: ${rule.value}"
      match {
        expr {
          expression = "evaluatePreconfiguredWaf('${rule.value}', {'sensitivity': 1})"
        }
      }
    }
  }

  rule {
    priority    = 1008
    action      = "deny(403)"
    description = "Log4Shell and other critical CVEs"
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('cve-canary')"
      }
    }
  }

  # --- Per-client-IP rate limit ---
  rule {
    priority    = 2000
    action      = "throttle"
    description = "Rate limit per client IP"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = var.rate_limit_requests_per_minute
        interval_sec = 60
      }
    }
  }

  # --- Default ---
  rule {
    priority    = 2147483647
    action      = "allow"
    description = "Default allow"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}

# ---------------------------------------------------------------- 4. Binary Authorization
resource "google_kms_key_ring" "binauthz" {
  project  = var.project_id
  name     = var.kms_keyring_name
  location = var.kms_location
}

resource "google_kms_crypto_key" "attestor" {
  name     = "build-attestor"
  key_ring = google_kms_key_ring.binauthz.id
  purpose  = "ASYMMETRIC_SIGN"

  version_template {
    algorithm        = "EC_SIGN_P256_SHA256"
    protection_level = "SOFTWARE"
  }

  lifecycle {
    prevent_destroy = false
  }
}

data "google_kms_crypto_key_version" "attestor" {
  crypto_key = google_kms_crypto_key.attestor.id
}

resource "google_kms_crypto_key_iam_member" "ci_signer" {
  crypto_key_id = google_kms_crypto_key.attestor.id
  role          = "roles/cloudkms.signerVerifier"
  member        = "serviceAccount:${var.ci_apps_sa}"
}

resource "google_container_analysis_note" "attestor" {
  project = var.project_id
  name    = "build-attestor-note"

  attestation_authority {
    hint {
      human_readable_name = "Built and signed by the trusted CI pipeline"
    }
  }
}

resource "google_binary_authorization_attestor" "build" {
  project = var.project_id
  name    = "build-attestor"

  attestation_authority_note {
    note_reference = google_container_analysis_note.attestor.name

    public_keys {
      id = data.google_kms_crypto_key_version.attestor.id
      pkix_public_key {
        public_key_pem      = data.google_kms_crypto_key_version.attestor.public_key[0].pem
        signature_algorithm = data.google_kms_crypto_key_version.attestor.public_key[0].algorithm
      }
    }
  }
}

resource "google_binary_authorization_policy" "this" {
  project = var.project_id

  # ENABLE = trust Google-maintained system images (kube-system, gke-managed-*, gmp-system...)
  global_policy_evaluation_mode = "ENABLE"

  default_admission_rule {
    evaluation_mode         = "REQUIRE_ATTESTATION"
    enforcement_mode        = var.binauthz_enforcement_mode
    require_attestations_by = [google_binary_authorization_attestor.build.name]
  }
}
