# -----------------------------------------------------------------------------
# Observability module
#   - Log sinks -> BigQuery (application logs, GKE cluster logs, LB logs)
#   - Grafana Cloud reader service account (BigQuery data source)
#   - Uptime checks (synthetic monitoring) + alert policies (SLO-style)
# Metrics (Managed Prometheus), traces (Cloud Trace), profiles (Cloud Profiler)
# and errors (Error Reporting) need no infra here: they are enabled on the
# clusters and in the app code.
# -----------------------------------------------------------------------------

resource "google_bigquery_dataset" "logs" {
  project                         = var.project_id
  dataset_id                      = "platform_logs"
  friendly_name                   = "Platform logs (Cloud Logging export)"
  location                        = var.bq_location
  default_partition_expiration_ms = var.log_retention_days * 24 * 60 * 60 * 1000
  delete_contents_on_destroy      = true
}

# GKE usage metering writes here (gke_cluster_resource_usage / _consumption tables)
resource "google_bigquery_dataset" "gke_usage" {
  project                    = var.project_id
  dataset_id                 = "gke_usage"
  friendly_name              = "GKE usage metering (CPU/memory per namespace)"
  location                   = var.bq_location
  delete_contents_on_destroy = true
}

resource "google_bigquery_dataset_iam_member" "grafana_usage" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.gke_usage.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.grafana.email}"
}

locals {
  sinks = {
    # Container stdout/stderr from our app namespaces
    app_logs = <<-EOT
      resource.type="k8s_container"
      resource.labels.namespace_name=("app1" OR "app2")
    EOT

    # Control plane (apiserver, scheduler, controller-manager), nodes, kube-system, k8s events
    gke_cluster_logs = <<-EOT
      resource.type=("k8s_cluster" OR "k8s_node" OR "k8s_control_plane_component" OR "gke_cluster")
      OR (resource.type="k8s_container" AND resource.labels.namespace_name="kube-system")
      OR (resource.type="k8s_pod" AND log_id("events"))
    EOT

    # Global external Application LB request logs (latency, status, Cloud Armor verdict)
    lb_logs = <<-EOT
      resource.type="http_load_balancer"
    EOT
  }
}

resource "google_logging_project_sink" "bq" {
  for_each = local.sinks

  project                = var.project_id
  name                   = "bq-${replace(each.key, "_", "-")}"
  destination            = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.logs.dataset_id}"
  filter                 = trimspace(each.value)
  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true # one table per log name, partitioned by day -> cheap time-range queries
  }
}

# Each sink writes with its own Google-managed identity; grant it access to the dataset only.
resource "google_bigquery_dataset_iam_member" "sink_writer" {
  for_each = google_logging_project_sink.bq

  project    = var.project_id
  dataset_id = google_bigquery_dataset.logs.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = each.value.writer_identity
}

# ---------------------------------------------------------------- Grafana reader
resource "google_service_account" "grafana" {
  project      = var.project_id
  account_id   = "grafana-reader"
  display_name = "Grafana Cloud - BigQuery and Monitoring read-only"
}

resource "google_service_account" "grafana_auth" {
  project      = var.project_id
  account_id   = "grafana-auth"
  display_name = "Grafana Cloud - key identity for reader impersonation"
}

resource "google_service_account_iam_member" "grafana_auth_impersonation" {
  service_account_id = google_service_account.grafana.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.grafana_auth.email}"
}

resource "google_project_iam_member" "grafana" {
  for_each = toset([
    "roles/bigquery.jobUser",  # run queries
    "roles/monitoring.viewer", # Cloud Monitoring / Managed Prometheus data source
    "roles/cloudtrace.user",   # Cloud Trace data source
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.grafana.email}"
}

resource "google_bigquery_dataset_iam_member" "grafana" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.logs.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.grafana.email}"
}

resource "google_bigquery_dataset_iam_member" "grafana_extra" {
  count = var.grafana_principal != "" ? 1 : 0

  project    = var.project_id
  dataset_id = google_bigquery_dataset.logs.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = var.grafana_principal
}

# ---------------------------------------------------------------- Alerting
resource "google_monitoring_notification_channel" "email" {
  count = var.alert_email != "" ? 1 : 0

  project      = var.project_id
  display_name = "Platform on-call e-mail"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}

locals {
  channels = google_monitoring_notification_channel.email[*].id
}

resource "google_monitoring_uptime_check_config" "app" {
  for_each = var.uptime_host != "" ? var.uptime_paths : {}

  project      = var.project_id
  display_name = "uptime-${each.key}"
  timeout      = "10s"
  period       = "60s"

  # Probes from several continents -> also proves global LB routing works
  selected_regions = ["USA", "EUROPE", "ASIA_PACIFIC"]

  http_check {
    path         = each.value
    port         = var.uptime_use_ssl ? 443 : 80
    use_ssl      = var.uptime_use_ssl
    validate_ssl = var.uptime_use_ssl
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.uptime_host
    }
  }

  # Alert policies reference the check id; they must switch to the new check before the old one is deleted.
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_monitoring_alert_policy" "uptime" {
  for_each = google_monitoring_uptime_check_config.app

  project      = var.project_id
  display_name = "Uptime failing - ${each.key}"
  combiner     = "OR"

  conditions {
    display_name = "Uptime check failed from 2+ regions"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.check_id=\"${each.value.uptime_check_id}\" AND resource.type=\"uptime_url\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "120s"
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.host"]
      }
    }
  }

  notification_channels = local.channels
}

resource "google_monitoring_alert_policy" "lb_5xx" {
  project      = var.project_id
  display_name = "Global LB 5xx ratio > 5%"
  combiner     = "OR"

  conditions {
    display_name = "5xx ratio"
    # PromQL (MQL is deprecated for new policies)
    condition_prometheus_query_language {
      duration            = "300s"
      evaluation_interval = "60s"
      query               = <<-EOT
        sum(rate(loadbalancing_googleapis_com:https_request_count{monitored_resource="https_lb_rule",response_code_class="500"}[5m]))
        /
        sum(rate(loadbalancing_googleapis_com:https_request_count{monitored_resource="https_lb_rule"}[5m]))
        > 0.05
      EOT
    }
  }

  notification_channels = local.channels
}

resource "google_monitoring_alert_policy" "pod_restarts" {
  project      = var.project_id
  display_name = "Pods restarting (crash loop)"
  combiner     = "OR"

  conditions {
    display_name = "Container restarts > 3 in 10 min"
    condition_threshold {
      filter          = "resource.type=\"k8s_container\" AND metric.type=\"kubernetes.io/container/restart_count\" AND (resource.label.namespace_name=\"app1\" OR resource.label.namespace_name=\"app2\")"
      comparison      = "COMPARISON_GT"
      threshold_value = 3
      duration        = "0s"
      aggregations {
        alignment_period   = "600s"
        per_series_aligner = "ALIGN_DELTA"
      }
    }
  }

  notification_channels = local.channels
}
