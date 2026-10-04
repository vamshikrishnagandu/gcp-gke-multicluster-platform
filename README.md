# GCP Multi-Region GKE Platform (Terraform)

Open-book assessment: a production-style platform on Google Cloud, built entirely with Terraform.

## What this project delivers
- A new GCP project (created by Terraform)
- Two GKE (Google Kubernetes Engine) clusters in two regions for high availability
- Two web applications with scalable multi-pod replicas
- Global load balancing with intelligent traffic distribution (multi-cluster Gateway)
- Full observability: Cloud Logging -> BigQuery for operational dashboards, Managed Prometheus -> Cloud Monitoring for live PromQL panels, plus Cloud Trace, Profiler and Error Reporting
- Managed Cloud Service Mesh on both Fleet memberships, with Envoy sidecars and MCS-backed app2-to-app1 traffic
- Built-in security, resilience and compliance controls (Workload Identity, Secret Manager, Cloud Armor, Binary Authorization)
- Data tier: Cloud SQL (HA + cross-region replica), Memorystore Redis (HA), Firestore (multi-region)
- CI/CD with GitHub Actions (keyless auth via Workload Identity Federation)

## Repository layout
| Path | Purpose |
|---|---|
| `docs/` | Design document, glossary, ADRs (Architecture Decision Records), learning log, runbook |
| `diagrams/` | draw.io source (`.drawio`), one per role |
| `terraform/bootstrap/` | One-time setup: project, billing, APIs, state bucket, CI identity |
| `terraform/modules/` | Reusable building blocks (network, gke, fleet, registry, data, security, observability) |
| `terraform/envs/prod/` | The environment that wires modules together |
| `apps/` | Source + Dockerfiles for app1 and app2 |
| `charts/` | Source of truth for app1/app2 and the config-cluster multi-cluster Gateway; Helm renders the Kubernetes resources |
| `grafana/` | Dashboard JSON, BigQuery schema and SQL queries |
| `scripts/` | `deploy.sh` - deploy both apps to both clusters |
| `.github/` | CI/CD workflows and issue templates |

## Roles played
| Role | Document | draw.io diagram |
|---|---|---|
| Architect | [solution-design](docs/architect/solution-design.md) | [01-architect-solution](diagrams/01-architect-solution.drawio) |
| Tech Lead | [engineering-standards](docs/techlead/engineering-standards.md), [ADRs](docs/techlead/adr/) | [02-techlead-repo-and-modules](diagrams/02-techlead-repo-and-modules.drawio) |
| DevOps | [setup-guide](docs/devops/setup-guide.md) | [03-devops-cicd](diagrams/03-devops-cicd.drawio) |
| SRE | [observability-and-dr](docs/sre/observability-and-dr.md) | [04-sre-observability-dr](diagrams/04-sre-observability-dr.drawio) |
| SecOps | [security-design](docs/secops/security-design.md) | [05-secops-security](diagrams/05-secops-security.drawio) |

BigQuery schema and Grafana queries: [grafana/bigquery-schema.md](grafana/bigquery-schema.md).

Kubernetes resources are managed through `charts/app` and `charts/gateway`. The old `k8s/` directories contain no tracked manifests and are not part of deployment; there is no separate YAML tree to apply by hand.

## Current operational notes
Public traffic is HTTPS only: a Google-managed certificate terminates TLS at the global load balancer and port 80 redirects with a 301. The hostname defaults to `<ip-with-dashes>.nip.io` (no domain purchase); set `domain` and `dns_zone_domain` to serve your own domain from a Cloud DNS zone. The VPC has separate node, ops/monitoring and proxy-only (load balancer) subnets per region. Human access is role-based (Dev read-only, Ops operate, SRE observe) through `team_members`, with no owner/editor grants. app1 reads its catalog from Cloud SQL using IAM database auth (schema and grants come from a Helm hook Job), and app2 caches that catalog in Redis over TLS with AUTH from Secret Manager; both fall back gracefully when a data store is unreachable.

Memorystore Redis remains a 1 GB regional `STANDARD_HA` primary with zonal failover. Cloud Scheduler exports an RDB to a versioned US multi-region bucket every 12 hours; noncurrent generations are retained for 30 days. The `us-east1` restore instance is opt-in and incurs compute cost only when enabled. Recovery is cold restore, not live cross-region replication; the RPO is up to 12 hours after a successful export, and restore RTO depends on instance creation and import. Google Cloud Monitoring email alerts still require the recipient to click Google's verification link.

Managed Cloud Service Mesh adds an estimated $0.50 per mesh client per month under standalone pricing. The 12 minimum app replicas are currently about $6/month before scale-out or custom metrics; check Cloud Billing for the active plan.

## Quick start
See [docs/devops/setup-guide.md](docs/devops/setup-guide.md).

## Learning
Every command executed is explained in [docs/learning-log.md](docs/learning-log.md).
Every problem encountered is logged as a GitHub Issue with the `issue-encountered` label.
