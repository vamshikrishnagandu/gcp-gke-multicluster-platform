# ADR 0003 - Cloud Logging -> BigQuery -> Grafana Cloud

**Status:** Accepted (required by the brief)

## Decision
- Three log sinks (`app_logs`, `gke_cluster_logs`, `lb_logs`) write to the `platform_logs` dataset, using partitioned tables.
- GKE usage metering writes to `gke_usage` (CPU/memory) for BigQuery resource-utilization panels; live app request metrics are sourced separately through Managed Prometheus and Cloud Monitoring.
- Grafana Cloud reads through the official BigQuery plugin, using the `grafana-reader` service account with read-only access to these datasets.
- Grafana Cloud also uses a Google Cloud Monitoring datasource, authenticated with the same JWT identity and `grafana-reader` impersonation, for Managed Prometheus PromQL panels.
- The provisioned overview dashboard keeps BigQuery panels for logs, errors, latency, resource usage, Cloud Armor and cluster traffic, and adds PromQL panels for app request rate, 5xx rate and p95 latency.

## Trade-offs
- Log sinks have a delay of about 1 minute, and usage metering is roughly hourly. Managed Prometheus/Cloud Monitoring supplies the live request-rate, 5xx and p95 panels.
- **Grafana Cloud can't use Workload Identity.** It needs a service account **key** (the one deliberate exception to ADR 0002). Mitigations: the credential-only service account can only impersonate `grafana-reader`; the key is stored only in Grafana's encrypted datasource settings and must be revoked when replaced.
- Cost is controlled with partition expiry (30 days) and `$__timeFilter` in every query.
