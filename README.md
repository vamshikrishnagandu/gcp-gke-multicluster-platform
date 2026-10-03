# GCP Multi-Region GKE Platform (Terraform)

Open-book assessment: a production-style platform on Google Cloud, built entirely with Terraform.

## What this project delivers
- A new GCP project (created by Terraform)
- Two GKE (Google Kubernetes Engine) clusters in two regions for high availability
- Two web applications with scalable multi-pod replicas
- Global load balancing with intelligent traffic distribution (multi-cluster Gateway)
- Full observability: logs, metrics, traces, errors (Cloud Logging -> BigQuery -> Grafana)
- Built-in security, resilience and compliance controls (Workload Identity, Secret Manager, Cloud Armor, Binary Authorization)
- Data tier: Cloud SQL (HA + cross-region replica), Memorystore Redis (HA), Firestore (multi-region)
- CI/CD with GitHub Actions (keyless auth via Workload Identity Federation)

## Repository layout
| Path | Purpose |
|---|---|
| `docs/` | Design document, glossary, ADRs (Architecture Decision Records), learning log, runbook |
| `diagrams/` | draw.io source (`.drawio`) and exported PNGs |
| `terraform/bootstrap/` | One-time setup: project, billing, APIs, state bucket, CI identity |
| `terraform/modules/` | Reusable building blocks (network, gke, fleet, data, security, observability) |
| `terraform/envs/prod/` | The environment that wires modules together |
| `apps/` | Source + Dockerfiles for app1 and app2 |
| `k8s/` | Kubernetes manifests (Kustomize base + per-cluster overlays) |
| `grafana/` | Dashboard JSON and BigQuery SQL queries |
| `.github/` | CI/CD workflows and issue templates |

## Roles played
Architect (design) -> Technical Lead (standards, decisions) -> DevOps (Terraform, CI/CD) -> SRE (observability, DR).

## Learning
Every command executed is explained in [docs/learning-log.md](docs/learning-log.md).
Every problem encountered is logged as a GitHub Issue with the `issue-encountered` label.
