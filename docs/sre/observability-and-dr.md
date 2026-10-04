# SRE - Observability, SLOs, HA/DR and Runbook

Diagrams: [`diagrams/04-sre-observability-dr.drawio`](../../diagrams/04-sre-observability-dr.drawio) (2 pages: observability and DR)

## SLOs
| SLI | SLO (30 days) | Source |
|---|---|---|
| Availability: non-5xx share of LB requests | 99.9 % | LB logs / `https/request_count` |
| Latency: p95 at the LB | < 300 ms | LB logs `httpRequest.latency` |
| Uptime from 3 continents | 99.9 % | Uptime checks |

## Signals (what, where)
| Signal | Collected by | Stored / viewed |
|---|---|---|
| Logs | GKE logging agent (JSON stdout) | Cloud Logging -> BigQuery `platform_logs` |
| Metrics | Managed Prometheus (`PodMonitoring`), system metrics | Cloud Monitoring; Grafana Cloud queries PromQL through the Google Cloud Monitoring datasource for app request rate, 5xx rate and p95 latency |
| Traces | OpenTelemetry -> Cloud Trace (20 % sampling) | Cloud Trace |
| Profiles | Cloud Profiler agent | Cloud Profiler |
| Errors | Stack traces in ERROR logs | Error Reporting |
| Synthetic | Uptime checks from USA / EUROPE / ASIA_PACIFIC | Monitoring alerts |

## Resilience features
Regional clusters (3 zones), topology spread, PDB `maxUnavailable: 1`, HPA 3-12, readiness probes, an exec `preStop` hook that allows a 10-second drain, and Deployment rolling updates with `maxUnavailable: 0`/`maxSurge: 1`. Managed Cloud Service Mesh injects an Envoy sidecar; app pods should be 2/2 ready. Maintenance windows are configured for weekends.

## Backups
| What | How | Retention |
|---|---|---|
| Cluster state (etcd equivalent) | Backup for GKE, daily, app namespaces + volumes + secrets | 14 days |
| Cloud SQL | automated backups (stored in us-east1) + PITR | 14 backups, 7 days of logs |
| Firestore | PITR + daily backup schedule | 7 days |
| Redis | RDB snapshot every 12 hours | latest |
| Images | Artifact Registry cleanup policies keep the newest 15 versions | 90 days |

Memorystore uses a 1 GB regional `STANDARD_HA` instance with a replica in another zone, automatic zonal failover and RDB snapshots every 12 hours. Native read replicas are region-local and require at least 5 GB nodes, so they scale reads rather than provide cross-region Redis DR. No cross-region replica or restore workflow is provisioned; regional Redis recovery needs a separate design, with its RTO/RPO still to be defined.

All Kubernetes resources are installed and updated from `charts/app` and `charts/gateway` using Helm. The old `k8s/` paths are empty/untracked and should not be used as a deployment source. CI builds, scans, attests and deploys images by digest; Helm release history is the rollback boundary.

## Runbook
**Region outage (automatic):** check `curl http://$IP/app1/`; the `region` field should show the surviving region. No action needed.

**Simulate a failover (game day):**
```bash
gcloud container clusters get-credentials gke-usc1 --region us-central1 --dns-endpoint
kubectl -n app1 scale deploy app1 --replicas=0   # HPA min=3 restores it; patch the HPA first for a longer test
for i in $(seq 20); do curl -s http://$IP/app1/ | jq -r .region; done   # -> us-east1 only
```

**Cloud SQL regional disaster (manual):**
```bash
gcloud sql instances promote-replica pg-replica-v1
# then update the apps' connection name to the replica and re-deploy
```

**Bad release:** prefer reverting the source commit and rerunning the app workflow so Helm remains the source of truth. For an immediate rollback, inspect `helm history app1 -n app1` and `helm rollback app1 <revision> -n app1` in both clusters, then reconcile from Git.

**Restore a namespace:** Console -> Backup for GKE -> create a restore plan from `gke-usc1-daily`.

**Alert email:** the Monitoring notification channel is enabled but email delivery is not verified until the recipient clicks Google's verification link.
