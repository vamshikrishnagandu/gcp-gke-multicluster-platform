# ADR 0003 - Cloud Logging -> BigQuery -> Grafana Cloud

**Status:** Accepted (required by the brief)

## Decision
- Three log sinks (`app_logs`, `gke_cluster_logs`, `lb_logs`) write to the `platform_logs` dataset, using partitioned tables.
- GKE usage metering writes to `gke_usage` (CPU/memory), so all four required panels can come from BigQuery.
- Grafana Cloud reads through the official BigQuery plugin, using the `grafana-reader` service account with read-only access to these datasets.

## Trade-offs
- Log sinks have a delay of about 1 minute, and usage metering is roughly hourly. For real-time CPU, the dashboard notes a Managed Prometheus (PromQL) alternative.
- **Grafana Cloud can't use Workload Identity.** It needs a service account **key** (the one deliberate exception to ADR 0002). Mitigations: read-only roles, the key is stored only in Grafana's encrypted data source settings, and it's rotated every 90 days.
- Cost is controlled with partition expiry (30 days) and `$__timeFilter` in every query.
