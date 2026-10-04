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
Memorystore Redis is a 1 GB regional `STANDARD_HA` instance with zonal automatic failover and 12-hour RDB snapshots. Cross-region Redis replication/recovery is not configured; a regional standby or restore design remains a separate decision. Google Cloud Monitoring's email notification channel also needs the recipient to complete Google's verification link before email alerts can be relied on.

Managed Cloud Service Mesh adds an estimated $0.50 per mesh client per month under standalone pricing. The 12 minimum app replicas are currently about $6/month before scale-out or custom metrics; check Cloud Billing for the active plan.

## Quick start
See [docs/devops/setup-guide.md](docs/devops/setup-guide.md).

## Learning
Every command executed is explained in [docs/learning-log.md](docs/learning-log.md).
Every problem encountered is logged as a GitHub Issue with the `issue-encountered` label.
