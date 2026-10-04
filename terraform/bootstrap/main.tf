# -----------------------------------------------------------------------------
# Bootstrap: everything that must exist BEFORE the main platform can be built.
#   1. The project itself (+ billing link)
#   2. All Google APIs used by the platform
#   3. Remote-state bucket for terraform/envs/prod
#   4. Keyless CI identity: Workload Identity Federation for GitHub Actions
#   5. A budget alert so a personal account never gets a surprise bill
# Runs once, from a laptop, with YOUR user credentials (ADC).
# -----------------------------------------------------------------------------

provider "google" {
  region = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Budgets API must be billed to a "quota project". User ADC has none by default,
# so this alias tells the provider to bill API calls to the new project.
provider "google" {
  alias                 = "billing"
  region                = var.region
  billing_project       = var.project_id
  user_project_override = true
}

locals {
  apis = [
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "billingbudgets.googleapis.com",
    "binaryauthorization.googleapis.com",
    "certificatemanager.googleapis.com",
    "cloudbilling.googleapis.com",
    "clouderrorreporting.googleapis.com",
    "cloudkms.googleapis.com",
    "cloudprofiler.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudtrace.googleapis.com",
    "compute.googleapis.com",
    "connectgateway.googleapis.com",
    "container.googleapis.com",
    "containeranalysis.googleapis.com",
    "containerscanning.googleapis.com",
    "dns.googleapis.com",
    "firestore.googleapis.com",
    "gkebackup.googleapis.com",
    "gkehub.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "mesh.googleapis.com",
    "monitoring.googleapis.com",
    "multiclusteringress.googleapis.com",
    "multiclusterservicediscovery.googleapis.com",
    "networksecurity.googleapis.com",
    "networkservices.googleapis.com",
    "ondemandscanning.googleapis.com",
    "redis.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "serviceusage.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
    "trafficdirector.googleapis.com",
  ]

  # Terraform CI identity: broad because it builds the whole platform.
  # Trade-off documented in docs/secops/security-design.md (section "CI identities").
  ci_terraform_roles = [
    "roles/editor",
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/container.admin",
    "roles/gkehub.admin",
    "roles/secretmanager.admin",
    "roles/binaryauthorization.policyEditor",
    "roles/binaryauthorization.attestorsAdmin",
    "roles/cloudkms.admin",
    "roles/cloudkms.publicKeyViewer",
    "roles/servicenetworking.networksAdmin",
    "roles/logging.configWriter",
    "roles/bigquery.admin",
    "roles/compute.securityAdmin",
  ]

  # Application CI identity: build, sign, deploy only.
  ci_apps_roles = [
    "roles/artifactregistry.writer",
    "roles/container.developer",
    "roles/cloudkms.signerVerifier",
    "roles/containeranalysis.notes.attacher",
    "roles/containeranalysis.occurrences.editor",
    "roles/binaryauthorization.attestorsViewer",
    "roles/ondemandscanning.admin", # vulnerability gate in the pipeline
    "roles/compute.viewer",         # deploy.sh reads the Gateway IP and TLS certificate name
    "roles/cloudsql.viewer",        # deploy.sh reads the Cloud SQL connection name
    "roles/redis.viewer",           # deploy.sh reads the Redis host and port
  ]
}

# ---------------------------------------------------------------- 1. Project
resource "google_project" "this" {
  project_id          = var.project_id
  name                = var.project_name
  billing_account     = var.billing_account
  org_id              = var.org_id != "" ? var.org_id : null
  folder_id           = var.folder_id != "" ? var.folder_id : null
  auto_create_network = false # delete the insecure "default" VPC with its open firewall rules
  deletion_policy     = var.project_deletion_policy
  labels              = var.labels
}

# ---------------------------------------------------------------- 2. APIs
resource "google_project_service" "apis" {
  for_each = toset(local.apis)

  project            = google_project.this.project_id
  service            = each.value
  disable_on_destroy = false # disabling APIs on destroy can orphan resources
}

resource "google_project_service_identity" "fleet_services" {
  provider = google-beta

  for_each = toset([
    "connectgateway.googleapis.com",
    "gkehub.googleapis.com",
    "multiclusterservicediscovery.googleapis.com",
  ])

  project    = google_project.this.project_id
  service    = each.value
  depends_on = [google_project_service.apis]
}

# ---------------------------------------------------------------- 3. State bucket
resource "google_storage_bucket" "tfstate" {
  project                     = google_project.this.project_id
  name                        = "${var.project_id}-tfstate"
  location                    = var.state_bucket_location
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true # every state write is a new object version -> roll back a corrupted state
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 20
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.apis]
}

# ---------------------------------------------------------------- 4. CI identity (keyless)
resource "google_iam_workload_identity_pool" "github" {
  project                   = google_project.this.project_id
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  description               = "OIDC federation for GitHub Actions - no service account keys."

  depends_on = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = google_project.this.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  # Restrict cloud access to main/prod jobs; pull_request claims do not distinguish fork PRs.
  attribute_condition = <<-EOT
    assertion.repository == '${var.github_repository}' &&
    assertion.repository_id == '${var.github_repository_id}' &&
    assertion.repository_owner_id == '${var.github_repository_owner_id}' &&
    assertion.ref == 'refs/heads/main' &&
    assertion.environment == 'prod' &&
    (assertion.event_name == 'push' || assertion.event_name == 'workflow_dispatch')
  EOT

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "ci_terraform" {
  project      = google_project.this.project_id
  account_id   = "ci-terraform"
  display_name = "CI - Terraform plan/apply"
}

resource "google_service_account" "ci_apps" {
  project      = google_project.this.project_id
  account_id   = "ci-apps"
  display_name = "CI - build, sign, deploy apps"
}

resource "google_project_iam_member" "ci_terraform" {
  for_each = toset(local.ci_terraform_roles)

  project = google_project.this.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ci_terraform.email}"
}

resource "google_project_iam_member" "ci_apps" {
  for_each = toset(local.ci_apps_roles)

  project = google_project.this.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ci_apps.email}"
}

resource "google_storage_bucket_iam_member" "ci_terraform_state" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ci_terraform.email}"
}

locals {
  github_principal = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

resource "google_service_account_iam_member" "ci_terraform_wif" {
  service_account_id = google_service_account.ci_terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.github_principal
}

resource "google_service_account_iam_member" "ci_apps_wif" {
  service_account_id = google_service_account.ci_apps.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.github_principal
}

# ---------------------------------------------------------------- 5. Budget alert
resource "google_billing_budget" "monthly" {
  provider        = google.billing
  billing_account = var.billing_account
  display_name    = "${var.project_id}-monthly"

  budget_filter {
    projects = ["projects/${google_project.this.number}"]
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency
      units         = tostring(var.budget_amount)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  depends_on = [google_project_service.apis]
}
