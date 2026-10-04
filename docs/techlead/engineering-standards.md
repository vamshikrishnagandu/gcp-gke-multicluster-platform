# Tech Lead - Engineering Standards

Diagram: [`diagrams/02-techlead-repo-and-modules.drawio`](../../diagrams/02-techlead-repo-and-modules.drawio)

## Terraform
- **Two stacks.** `bootstrap` runs once from a laptop with local state, because the state bucket doesn't exist yet. `envs/prod` uses GCS remote state and is run by CI.
- **Modules** each own one concern and talk to each other only through inputs and outputs.
- Provider version pinned (`~> 6.40`), and `.terraform.lock.hcl` is committed.
- `for_each` over a map of regions (never `count`), so adding a third region is a data change, not a code change.
- Deletion safety is controlled by variables (`deletion_protection`, `project_deletion_policy`).

## Quality gates (every PR)
| Gate | Tool |
|---|---|
| Formatting | `terraform fmt -check -recursive` |
| Lint + GCP rules | `tflint` + google ruleset (`.tflint.hcl`) |
| Security policy | `checkov` (`.checkov.yaml`; every skip has a reason) |
| Python | `ruff` + Flask test-client smoke test |
| Kubernetes | `helm lint` and `helm template` for both charts |

## Kubernetes
- Helm release per app per cluster; the `platform-gateway` release is installed only on the config cluster.
- `charts/app` parameterizes app1/app2 without changing their resource names; `charts/gateway` owns Gateway, routes, health checks, and backend policies.
- `scripts/deploy.sh` resolves tags to immutable digests and runs `helm upgrade --install`. Images are always referenced **by digest**.
- Every Deployment has requests/limits, probes, a PDB, an HPA, topology spread and a restricted securityContext.

## Git workflow
- `main` is protected and changes go in through PRs. The Terraform plan is posted on the PR, and apply runs only after merge (with `prod` environment approval).
- Every problem we hit becomes a GitHub Issue labelled `issue-encountered` and is mirrored in [`docs/learning-log.md`](../learning-log.md).

## ADRs
| # | Decision |
|---|---|
| [0001](adr/0001-gateway-api-multicluster.md) | Multi-cluster Gateway API for global load balancing |
| [0002](adr/0002-keyless-auth.md) | Keyless auth everywhere (WIF for CI, Workload Identity for pods) |
| [0003](adr/0003-logs-to-bigquery-grafana.md) | Cloud Logging -> BigQuery -> Grafana Cloud |
| [0004](adr/0004-https-and-dns.md) | HTTPS with a managed certificate and a Cloud Domains domain on Cloud DNS |
| [0005](adr/0005-data-tier-access.md) | IAM-auth Cloud SQL for app1, TLS Redis read-through cache for app2 |
