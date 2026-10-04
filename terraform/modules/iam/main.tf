# -----------------------------------------------------------------------------
# IAM module - human access by team (Dev / Ops / SRE). CI/CD and workload
# identities are created in bootstrap and the security module.
# Least privilege: nobody gets owner/editor; production changes go through CI.
# Grant to Google Groups (group:team@example.com) so people join/leave without Terraform.
# -----------------------------------------------------------------------------

locals {
  team_roles = {
    # Read-only: see logs, traces, errors and cluster state; pull images. Ships via CI, not by hand.
    developers = [
      "roles/container.viewer",
      "roles/logging.viewer",
      "roles/monitoring.viewer",
      "roles/cloudtrace.user",
      "roles/errorreporting.viewer",
      "roles/cloudprofiler.user",
      "roles/artifactregistry.reader",
    ]
    # Operate the platform: change Kubernetes objects, push images, tunnel to private hosts.
    operators = [
      "roles/container.developer",
      "roles/artifactregistry.writer",
      "roles/compute.networkViewer",
      "roles/cloudsql.viewer",
      "roles/redis.viewer",
      "roles/logging.viewer",
      "roles/monitoring.viewer",
      "roles/iap.tunnelResourceAccessor",
    ]
    # Reliability: edit alerts/dashboards, investigate incidents, query logs in BigQuery.
    sres = [
      "roles/container.viewer",
      "roles/monitoring.editor",
      "roles/logging.viewer",
      "roles/cloudtrace.user",
      "roles/errorreporting.admin",
      "roles/cloudprofiler.user",
      "roles/cloudsql.viewer",
      "roles/redis.viewer",
      "roles/bigquery.dataViewer",
      "roles/bigquery.jobUser",
    ]
  }

  members = {
    developers = var.developers
    operators  = var.operators
    sres       = var.sres
  }

  # Keyed by role+member so a role shared by several teams is bound once.
  bindings = merge([
    for team, roles in local.team_roles : {
      for pair in setproduct(roles, local.members[team]) :
      "${pair[0]}|${pair[1]}" => { role = pair[0], member = pair[1] }
    }
  ]...)
}

resource "google_project_iam_member" "team" {
  for_each = local.bindings

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}
