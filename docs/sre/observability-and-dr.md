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
| Metrics | Managed Prometheus (`PodMonitoring`), system metrics | Cloud Monitoring |
| Traces | OpenTelemetry -> Cloud Trace (20 % sampling) | Cloud Trace |
| Profiles | Cloud Profiler agent | Cloud Profiler |
| Errors | Stack traces in ERROR logs | Error Reporting |
| Synthetic | Uptime checks from USA / EUROPE / ASIA_PACIFIC | Monitoring alerts |

## Resilience features
Regional clusters (3 zones), topology spread, PDB `maxUnavailable: 1`, HPA 3-12, readiness probe + `preStop` sleep (so the LB drains the pod before it stops), surge upgrades, maintenance windows at weekends.

## Backups
| What | How | Retention |
|---|---|---|
| Cluster state (etcd equivalent) | Backup for GKE, daily, app namespaces + volumes + secrets | 14 days |
| Cloud SQL | automated backups (stored in us-east1) + PITR | 14 backups, 7 days of logs |
| Firestore | PITR + daily backup schedule | 7 days |
| Redis | RDB snapshot every 12 hours | latest |
| Images | Artifact Registry cleanup policies keep the newest 15 versions | 90 days |

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

**Bad release:** `kubectl -n app1 rollout undo deploy/app1` in both clusters, or re-run CI for the previous commit.

**Restore a namespace:** Console -> Backup for GKE -> create a restore plan from `gke-usc1-daily`.
