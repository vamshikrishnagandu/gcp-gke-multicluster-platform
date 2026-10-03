# SecOps - Security Design and Threat Model

Diagram: [`diagrams/05-secops-security.drawio`](../../diagrams/05-secops-security.drawio)

## Controls required by the brief
| Control | Where |
|---|---|
| Workload Identity | `modules/security` (GSA per app + `workloadIdentityUser`), KSA annotation in `k8s/base/*/serviceaccount.yaml` |
| Secret Manager | `<app>-api-key`, `cloudsql-admin-password`; 2-region replication; per-secret IAM |
| Private GKE clusters | `enable_private_nodes`, Cloud NAT, IAM-authorised DNS control-plane endpoint |
| Cloud Armor WAF | `edge-waf` policy, attached via `GCPBackendPolicy` |
| Binary Authorization | KMS attestor + `REQUIRE_ATTESTATION` policy, enforced on both clusters |

## Threat model (STRIDE summary)
| Threat | Mitigation |
|---|---|
| Stolen CI credentials | No keys exist; WIF tokens accepted only from this repo; `prod` environment approval |
| Malicious or unscanned image | Immutable tags, CRITICAL vulnerability gate, signed attestation, Binary Authorization |
| Web attacks (SQLi/XSS) | Cloud Armor OWASP CRS |
| L7 DDoS | Rate limit + Adaptive Protection + Google edge |
| Lateral movement in the cluster | NetworkPolicy default-deny, PSA `restricted`, no SA token automount |
| Pod escape to node identity | GKE metadata server, least-privilege node SA, shielded nodes |
| Data exfiltration from the DB | Private IP only, TLS required, IAM DB auth |
| Secret leakage in git | `.gitignore`, no tfvars committed, secrets created by Terraform and never printed |

## CI identities
`ci-terraform` is broad (`roles/editor` + IAM admin roles) because it builds the whole platform. This is an **accepted risk**, mitigated by: repo-pinned WIF, `main`-only apply, and environment approval. For production I'd split it per module, or use the Privileged Access Manager for just-in-time elevation.

## Accepted risks (`.checkov.yaml`)
Google-managed encryption instead of customer-managed keys (CMEK), a public (IAM-protected) control-plane DNS endpoint, and a Grafana service account key (ADR 0003).

## Compliance evidence
Cloud Audit Logs (admin activity, always on), log exports to BigQuery, Binary Authorization audit logs, Cloud Armor verbose logs, VPC flow logs and firewall logs.
