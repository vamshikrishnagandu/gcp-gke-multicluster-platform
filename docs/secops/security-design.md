# SecOps - Security Design and Threat Model

Diagram: [`diagrams/05-secops-security.drawio`](../../diagrams/05-secops-security.drawio)

## Controls required by the brief
| Control | Where |
|---|---|
| Workload Identity | `modules/security` (GSA per app + `workloadIdentityUser`), KSA annotation in `charts/app/templates/serviceaccount.yaml` |
| Secret Manager | `<app>-api-key`, `cloudsql-admin-password`; 2-region replication; per-secret IAM |
| Private GKE clusters | `enable_private_nodes`, Cloud NAT, IAM-authorised DNS control-plane endpoint |
| Cloud Armor WAF | `edge-waf` policy, attached via `GCPBackendPolicy` |
| Binary Authorization | KMS attestor + `REQUIRE_ATTESTATION` policy, enforced on both clusters |
| TLS in transit | Google-managed certificate terminates HTTPS at the global LB (`app.vamshicloudlab.com`); port 80 only redirects; Cloud SQL `ENCRYPTED_ONLY`; Redis TLS + AUTH |
| Segregated subnets | Per region: nodes, ops/monitoring and proxy-only (load balancer) subnets; logged deny-all ingress; ops range allowed internally |
| RBAC for Dev, Ops, SRE | `modules/iam`: Dev read-only, Ops operate (`container.developer`, registry writer, IAP tunnel), SRE observe (monitoring editor, logging, BigQuery read); no owner/editor; bind Google Groups through `team_members` |
| Database access | app1 logs in to Cloud SQL with IAM auth (`cloudsql.instanceUser`, `SELECT` on `catalog.items` only); the admin password is readable only by the `wl-db-init` schema Job; Redis AUTH/CA secrets readable only by `wl-app2` |

## Threat model (STRIDE summary)
| Threat | Mitigation |
|---|---|
| Stolen CI credentials | No CI keys exist; WIF checks immutable repository/owner IDs, `main`, the `prod` environment and permitted push/manual events; pull requests receive static checks only |
| Malicious or unscanned image | Immutable SHA tags, CRITICAL vulnerability gate, KMS-backed digest attestation in primary and recovery registries, enforced Binary Authorization |
| Web attacks (SQLi/XSS) | Cloud Armor OWASP CRS |
| L7 DDoS | Rate limit + Adaptive Protection + Google edge |
| Lateral movement in the cluster | NetworkPolicy default-deny, PSA `restricted`, no SA token automount |
| Pod escape to node identity | GKE metadata server, least-privilege node SA, shielded nodes |
| Data exfiltration from the DB | Private IP only, TLS required, IAM DB auth, read-only grant for the app user |
| Eavesdropping on user traffic | HTTPS only with a managed certificate; HTTP is redirected; DNSSEC on the zone |
| Domain hijack or expiry | Registrar lock and WHOIS privacy; auto-renew; registrant email verified |
| Secret leakage in git | `.gitignore`, no tfvars committed, secrets created by Terraform and never printed |

## CI identities
`ci-terraform` is broad (`roles/editor` + IAM admin roles) because it builds the whole platform. This is an **accepted risk**, mitigated by: repo-pinned WIF, `main`-only apply, and environment approval. For production I'd split it per module, or use the Privileged Access Manager for just-in-time elevation.

The app workflow also runs Ruff and app smoke tests, lints/renders both Helm charts, builds and mirrors images, blocks CRITICAL scan findings, signs both registry digests, then deploys by digest through `scripts/deploy.sh`. Terraform CI uses `pipefail`, validates required inputs, scopes `ALERT_EMAIL` as an encrypted secret, and blocks plans containing deletions.

## Accepted risks (`.checkov.yaml`)
Google-managed encryption instead of customer-managed keys (CMEK), a public (IAM-protected) control-plane DNS endpoint, and the operator-managed Grafana service-account key used for JWT authentication and `grafana-reader` impersonation (ADR 0003). The key is stored in Grafana's encrypted datasource settings, never in the repository.

## Compliance evidence
Cloud Audit Logs (admin activity, always on), log exports to BigQuery, Binary Authorization audit logs, Cloud Armor verbose logs, VPC flow logs and firewall logs.
