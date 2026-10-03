# Architect - Solution Design

Diagram: [`diagrams/01-architect-solution.drawio`](../../diagrams/01-architect-solution.drawio) (open with the draw.io VS Code extension or app.diagrams.net)

## 1. Requirements -> design
| Requirement | Design answer |
|---|---|
| New GCP project | `terraform/bootstrap` creates it, links billing, enables APIs |
| Two GKE clusters, HA / multi-region | Regional private clusters `gke-usc1` (us-central1) and `gke-use1` (us-east1), 3 zones each |
| Two web apps, multi-pod | `app1` (catalog) and `app2` (orders), 3-12 replicas each per cluster (HPA) |
| Global LB, intelligent routing | Multi-cluster Gateway -> one global external Application LB, anycast IP, closest-healthy-region routing, NEG backends |
| Logs, metrics, traces, errors | Cloud Logging -> BigQuery -> Grafana; Managed Prometheus; Cloud Trace; Profiler; Error Reporting |
| Security, resilience, compliance | Cloud Armor, Workload Identity, Secret Manager, private clusters, Binary Authorization; HA data tier + backups |

## 2. Request flow (Steps 1-6 of the brief)
1. **DNS / anycast IP**: the user resolves to one global IP, and the request enters Google's network at the nearest edge location.
2. **Cloud Armor** checks the request against the OWASP rules and per-IP rate limit before any backend sees it.
3. **Global LB -> cluster NEGs**: proximity routing sends the request to the closest cluster. If a region's health checks fail, traffic moves to the other region.
4. **Gateway controller**: `HTTPRoute` sends `/app1` to the `app1` ServiceImport and `/app2` to the `app2` ServiceImport.
5. **Service -> pods**: container-native load balancing sends traffic straight to pod IPs. Replicas give resiliency, the HPA scales them out, and rolling updates use `maxUnavailable: 0`.
6. **Response** returns along the same path (pod -> LB -> user). Latency, logs and the trace are captured at both the LB and the app.

`app2 /orders` calls `app1` through `app1.app1.svc.clusterset.local` (Multi-Cluster Services), so one user request produces a trace with spans from both services.

## 3. Key decisions
See [ADRs](../techlead/adr/). Summary:
- **Gateway API (multi-cluster)** over the older MultiClusterIngress CRD, because Gateway API is the standard Google is investing in.
- **GKE Standard** over Autopilot, so I could show node pools, shielded nodes and Spot nodes explicitly. Autopilot would be the simpler production choice.
- **us-central1 + us-east1**: both are low-cost regions, they're far enough apart to be separate failure domains, and both sit inside Firestore's `nam5` multi-region.
- **Single project, single prod environment**: matches the brief. A real setup would add dev and staging projects using the same modules.

## 4. Cost estimate (personal account, approx. per month)
| Item | ~USD |
|---|---|
| 2 regional clusters (cluster management fee, 1 cluster covered by the free tier) | 73 |
| 4-6 x e2-standard-2 Spot nodes | 50-75 |
| Cloud SQL HA db-custom-1-3840 + replica | 110 |
| Redis Standard 1 GB | 50 |
| Global LB + Cloud Armor policy | 25 |
| Logging/BigQuery/Trace (low traffic) | <10 |

**Tear it down when you're not using it:** `terraform destroy` in `envs/prod` (set `deletion_protection=false` first).
