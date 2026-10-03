# BigQuery schema used by Grafana

Cloud Logging sinks with `use_partitioned_tables = true` create **one table per log name**, partitioned by `timestamp` (daily).
Table names are derived from the log ID (`/` and `.` become `_`).

| Dataset.table | Written by | Log / source | Used by panel |
|---|---|---|---|
| `platform_logs.stdout` | sink `bq-app-logs` | container stdout of app1/app2 (JSON) | 1 Error rate, 3 Latency (option B) |
| `platform_logs.stderr` | sink `bq-app-logs` | container stderr | troubleshooting |
| `platform_logs.events` | sink `bq-gke-cluster-logs` | Kubernetes events | 2 Pod restarts, HPA events |
| `platform_logs.cloudaudit_googleapis_com_activity` | sink `bq-gke-cluster-logs` | control-plane audit logs | security queries |
| `platform_logs.container_googleapis_com_cluster_autoscaler_visibility` | sink `bq-gke-cluster-logs` | node autoscaler decisions | capacity analysis |
| `platform_logs.requests` | sink `bq-lb-logs` | global external ALB request logs | 3 Latency (option A) |
| `gke_usage.gke_cluster_resource_consumption` | GKE usage metering | CPU / memory actually used | 4 Resource utilisation |
| `gke_usage.gke_cluster_resource_usage` | GKE usage metering | CPU / memory requested | 4 (requests vs usage) |

> Tables appear only **after the first matching log entry** arrives. An empty dataset right after `terraform apply` is normal.

## Key columns (LogEntry -> BigQuery)

| Column | Type | Meaning |
|---|---|---|
| `timestamp` | TIMESTAMP | event time (partition column) |
| `severity` | STRING | DEFAULT / INFO / WARNING / ERROR / CRITICAL |
| `resource.type` | STRING | `k8s_container`, `k8s_node`, `http_load_balancer` ... |
| `resource.labels.cluster_name` | STRING | `gke-usc1` / `gke-use1` |
| `resource.labels.namespace_name` | STRING | `app1` / `app2` |
| `resource.labels.pod_name` | STRING | pod |
| `jsonPayload.message` | STRING | log message (apps log JSON -> parsed into jsonPayload) |
| `jsonPayload.latency_ms` | FLOAT | server-side latency written by the app |
| `jsonPayload.httprequest.status` | INTEGER | HTTP status in app access logs |
| `httpRequest.latency` | FLOAT (seconds) | LB-measured latency (lb_logs only) |
| `httpRequest.status` | INTEGER | status returned to the client (lb_logs only) |
| `jsonPayload.enforcedsecuritypolicy.outcome` | STRING | Cloud Armor ACCEPT / DENY (lb_logs) |
| `trace` | STRING | `projects/P/traces/ID` - links a log line to Cloud Trace |

> **Gotcha:** BigQuery column names are **lower-cased** for nested `jsonPayload` fields
> (`httpRequest` inside jsonPayload becomes `jsonpayload.httprequest`). Top-level LogEntry fields keep camelCase (`httpRequest.latency`).

## Queries
See [`queries/`](queries/) - one file per dashboard panel. `PROJECT_ID` is replaced with your project ID when importing.

## Cost guard-rails
- Every query uses `$__timeFilter(timestamp)` -> BigQuery scans only the matching daily partitions.
- `default_partition_expiration_ms` = 30 days -> old partitions are deleted automatically.
