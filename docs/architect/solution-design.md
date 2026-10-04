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

## 2. Request flow (Steps 1-6 of the brief)
1. **DNS / anycast IP**: the user resolves to one global IP, and the request enters Google's network at the nearest edge location.
2. **Cloud Armor** checks the request against the OWASP rules and per-IP rate limit before any backend sees it.
3. **Global LB -> cluster NEGs**: proximity routing sends the request to the closest cluster. If a region's health checks fail, traffic moves to the other region.
4. **Gateway controller**: `HTTPRoute` sends `/app1` to the `app1` ServiceImport and `/app2` to the `app2` ServiceImport.
5. **Service -> pods**: container-native load balancing sends traffic straight to pod IPs. Three replicas per app per cluster are spread across zones, the HPA can scale to 12, and Helm rollouts use `maxUnavailable: 0`. Managed Service Mesh injects an Envoy sidecar into each app pod.
6. **Response** returns along the same path (pod -> LB -> user). Latency, logs and the trace are captured at both the LB and the app.

`app2 /orders` calls `app1` through the MCS-imported service name exposed in the ServiceImport's `net.gke.io/derived-service` annotation: `http://<derived-service>.app1.svc.cluster.local:8080/app1/items`. This mesh-compatible DNS name works with Envoy; `.svc.clusterset.local` is not used for this mesh path.

## 3. Runtime and delivery
`charts/app` is the source of truth for app namespaces, Deployments, Services, HPAs, NetworkPolicies, PodMonitoring, PDBs, ServiceAccounts and ServiceExports. `charts/gateway` owns the config-cluster Gateway, HTTPRoutes and policies. `scripts/deploy.sh` resolves image digests, reads the MCS-derived app1 service name in each cluster, and upgrades both app releases plus the config-cluster Gateway. The old `k8s/` directories are empty and untracked; they are not used by CI or deployment.

The app workflow runs lint/smoke tests and Helm lint/render checks, builds immutable images to the primary and recovery Artifact Registry locations, blocks CRITICAL vulnerabilities, creates KMS-backed Binary Authorization attestations, then deploys by digest. Pull requests run static checks only; privileged cloud deployment is limited to the `main` production environment.

## 4. Key decisions
See [ADRs](../techlead/adr/). Summary:
- **Gateway API (multi-cluster)** over the older MultiClusterIngress CRD, because Gateway API is the standard Google is investing in.
- **Managed Cloud Service Mesh (`TRAFFIC_DIRECTOR`)** on both Fleet memberships for sidecar-based service-to-service traffic and managed control planes.
- **Helm** as the single Kubernetes source of truth, replacing the superseded Kustomize manifests.
- **GKE Standard** over Autopilot, so I could show node pools, shielded nodes and Spot nodes explicitly. Autopilot would be the simpler production choice.
- **us-central1 + us-east1**: both are low-cost regions, they're far enough apart to be separate failure domains, and both sit inside Firestore's `nam5` multi-region.
- **Single project, single prod environment**: matches the brief. A real setup would add dev and staging projects using the same modules.

## 5. Current limitations
Memorystore is a 1 GB regional `STANDARD_HA` cache with a zone replica, automatic zonal failover and 12-hour RDB snapshots. Its native read replicas are region-local and require at least 5 GB nodes; cross-region Redis replication or a regional restore workflow is not configured. Do not treat Redis as cross-region protected until a separate recovery design is implemented.

The Google Cloud Monitoring email notification channel exists but is not verified until the recipient completes Google's verification email.

## 6. Cost estimate (personal account, approx. per month)
| Item | ~USD |
|---|---|
| 2 regional clusters (cluster management fee, 1 cluster covered by the free tier) | 73 |
| 4-6 x e2-standard-2 Spot nodes | 50-75 |
| Cloud SQL HA db-custom-1-3840 + replica | 110 |
| Redis Standard 1 GB | 50 |
| Global LB + Cloud Armor policy | 25 |
| Logging/BigQuery/Trace (low traffic) | <10 |
| Managed Cloud Service Mesh (12 minimum app clients, standalone estimate) | ~6 |

**Tear it down when you're not using it:** `terraform destroy` in `envs/prod` (set `deletion_protection=false` first).
