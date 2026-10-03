# -----------------------------------------------------------------------------
# Artifact Registry: the ONLY place images may come from (enforced by Binary
# Authorization). Multi-region location = replicated across US regions.
# -----------------------------------------------------------------------------

resource "google_artifact_registry_repository" "docker" {
  project       = var.project_id
  location      = var.location
  repository_id = var.repository_id
  description   = "Application container images"
  format        = "DOCKER"

  docker_config {
    immutable_tags = true # a tag can never be overwritten -> what was tested is what runs
  }

  # Dry-run first lets you see what WOULD be deleted (Cloud Audit Logs) before it happens.
  cleanup_policy_dry_run = var.cleanup_dry_run

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 15
    }
  }

  cleanup_policies {
    id     = "delete-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "1209600s" # 14 days
    }
  }

  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      tag_state  = "ANY"
      older_than = "7776000s" # 90 days (KEEP rule above still protects the newest 15)
    }
  }

  labels = var.labels
}
