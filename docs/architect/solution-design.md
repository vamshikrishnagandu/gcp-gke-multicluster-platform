# Architect - Solution Design

Diagram: [`diagrams/01-architect-solution.drawio`](../../diagrams/01-architect-solution.drawio) (open with the draw.io VS Code extension or app.diagrams.net)

## 1. Requirements -> design
| Requirement | Design answer |
|---|---|
| New GCP project | `terraform/bootstrap` creates it, links billing, enables APIs |
| Two GKE clusters, HA / multi-region | Regional private clusters `gke-usc1` (us-central1) and `gke-use1` (us-east1), 3 zones each |
| Two web apps, multi-pod | `app1` (catalog) and `app2` (orders), 3-12 replicas each per cluster (HPA) |
| Global LB, intelligent routing | Multi-cluster Gateway -> one global external Application LB, anycast IP, closest-healthy-region routing, NEG backends |
| Logs, metrics, traces, errors | Cloud Logging -> BigQuery for log/usage panels; Managed Prometheus -> Cloud Monitoring -> Grafana Cloud for PromQL; Cloud Trace; Profiler; Error Reporting |
| Security, resilience, compliance | Cloud Armor, Workload Identity, Secret Manager, private clusters, Binary Authorization; HA data tier + backups |
| HTTPS and a friendly name | Domain `vamshicloudlab.com` registered in Cloud Domains, public Cloud DNS zone, `app.vamshicloudlab.com` A record to the global IP, Google-managed certificate on the Gateway, port 80 redirects to HTTPS |
| Segregated subnets | Per region: GKE nodes (with pod/service ranges), ops/monitoring subnet, proxy-only subnet reserved for Envoy load balancers |
| IAM roles for Dev, Ops, SRE and CI/CD | `modules/iam` (Dev read-only, Ops operate, SRE observe) from `team_members`; CI/CD and workload identities in bootstrap and `modules/security` |
| Apps use the data tier | app1 reads its catalog from Cloud SQL (IAM auth, private IP); app2 caches it in Memorystore Redis (TLS + AUTH); Firestore holds hit counters |

## 2. Request flow (Steps 1-6 of the brief)
1. **DNS / anycast IP**: `app.vamshicloudlab.com` resolves (Cloud DNS) to one global IP, and the request enters Google's network at the nearest edge location. TLS terminates at the load balancer with a Google-managed certificate; port 80 only returns a 301 to HTTPS.
2. **Cloud Armor** checks the request against the OWASP rules and per-IP rate limit before any backend sees it.
3. **Global LB -> cluster NEGs**: proximity routing sends the request to the closest cluster. If a region's health checks fail, traffic moves to the other region.
4. **Gateway controller**: `HTTPRoute` sends `/app1` to the `app1` ServiceImport and `/app2` to the `app2` ServiceImport.
5. **Service -> pods**: container-native load balancing sends traffic straight to pod IPs. Three replicas per app per cluster are spread across zones, the HPA can scale to 12, and Helm rollouts use `maxUnavailable: 0`. Managed Service Mesh injects an Envoy sidecar into each app pod.
6. **Response** returns along the same path (pod -> LB -> user). Latency, logs and the trace are captured at both the LB and the app.

`app2 /orders` calls `app1` through the MCS-imported service name exposed in the ServiceImport's `net.gke.io/derived-service` annotation: `http://<derived-service>.app1.svc.cluster.local:8080/app1/items`. This mesh-compatible DNS name works with Envoy; `.svc.clusterset.local` is not used for this mesh path.

## 3. Data access
- **app1 -> Cloud SQL:** the Cloud SQL Python Connector over private IP with IAM database authentication (the pod's Workload Identity, no password). A Helm post-install/upgrade Job (`db-init`, KSA `app1/db-init` -> `wl-db-init`, the only identity allowed to read the admin password) creates schema `catalog`, table `items` and grants `SELECT` to `wl-app1`. If the database is unreachable, `/app1/items` serves a static list and reports `items_source: fallback`.
- **app2 -> Redis:** read-through cache of the app1 catalog for 30 seconds. The AUTH string and server CA come from Secret Manager (`redis-auth-string`, `redis-ca-cert`; only `wl-app2` can read them) and the connection uses TLS. The response reports `cache: hit | miss | unavailable | disabled`; Redis outages never fail the request.
- **Firestore:** hit counter for app1 via Workload Identity.

## 4. Runtime and delivery
`charts/app` is the source of truth for app namespaces, Deployments, Services, HPAs, NetworkPolicies, PodMonitoring, PDBs, ServiceAccounts and ServiceExports. `charts/gateway` owns the config-cluster Gateway, HTTPRoutes and policies. `scripts/deploy.sh` resolves image digests, reads the MCS-derived app1 service name in each cluster, looks up the Cloud SQL connection name, Redis host/port and the TLS certificate names, and upgrades both app releases plus the config-cluster Gateway. The old `k8s/` directories are empty and untracked; they are not used by CI or deployment.

The app workflow runs lint/smoke tests and Helm lint/render checks, builds immutable images to the primary and recovery Artifact Registry locations, blocks CRITICAL vulnerabilities, creates KMS-backed Binary Authorization attestations, then deploys by digest. Pull requests run static checks only; privileged cloud deployment is limited to the `main` production environment.

## 5. Key decisions
See [ADRs](../techlead/adr/). Summary:
- **Gateway API (multi-cluster)** over the older MultiClusterIngress CRD, because Gateway API is the standard Google is investing in.
- **Managed Cloud Service Mesh (`TRAFFIC_DIRECTOR`)** on both Fleet memberships for sidecar-based service-to-service traffic and managed control planes.
- **Helm** as the single Kubernetes source of truth, replacing the superseded Kustomize manifests.
- **GKE Standard** over Autopilot, so I could show node pools, shielded nodes and Spot nodes explicitly. Autopilot would be the simpler production choice.
- **us-central1 + us-east1**: both are low-cost regions, they're far enough apart to be separate failure domains, and both sit inside Firestore's `nam5` multi-region.
- **Single project, single prod environment**: matches the brief. A real setup would add dev and staging projects using the same modules.

## 6. Current limitations
Memorystore remains a 1 GB regional `STANDARD_HA` primary with automatic zonal failover. Cloud Scheduler exports RDB data every 12 hours to a versioned US multi-region Cloud Storage bucket; archived generations are retained for 30 days. This is cold recovery, not synchronous cross-region replication. If an export succeeds on schedule, the recovery point is at most 12 hours old. The `us-east1` Redis instance is created only when recovery is needed, so its RTO is the provisioning plus import time and has not yet been measured. The app2 cache is optional: it degrades to calling app1 directly, so a Redis outage costs latency, not availability.

The Google Cloud Monitoring email notification channel exists but is not verified until the recipient completes Google's verification email.

## 7. Cost estimate (personal account, approx. per month)
| Item | ~USD |
|---|---|
| 2 regional clusters (cluster management fee, 1 cluster covered by the free tier) | 73 |
| 4-6 x e2-standard-2 Spot nodes | 50-75 |
| Cloud SQL HA db-custom-1-3840 + replica | 110 |
| Redis Standard 1 GB | 50 |
| Global LB + Cloud Armor policy | 25 |
| Logging/BigQuery/Trace (low traffic) | <10 |
| Managed Cloud Service Mesh (12 minimum app clients, standalone estimate) | ~6 |
| Domain `vamshicloudlab.com` (12 per year) + Cloud DNS zone | ~1.2 |

**Tear it down when you're not using it:** `terraform destroy` in `envs/prod` (set `deletion_protection=false` first).
