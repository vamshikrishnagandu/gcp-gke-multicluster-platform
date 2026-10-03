# ADR 0002 - Keyless authentication everywhere

**Status:** Accepted

## Context
Service account JSON keys are the most common cause of GCP credential leaks.

## Decision
- **GitHub Actions -> GCP:** Workload Identity Federation (OIDC). The provider's `attribute_condition` only accepts tokens from this one repository.
- **Pods -> GCP APIs:** GKE Workload Identity. Each app has its own Google service account (`wl-app1`, `wl-app2`), bound to the matching Kubernetes service account.
- **Pods -> Cloud SQL:** IAM database authentication, so there are no DB passwords in the apps.
- **Humans:** `gcloud auth login` plus ADC, and the clusters are reached through the IAM-authorised DNS endpoint.

## Consequences
- No secrets are stored in GitHub; only non-sensitive repository *variables*.
- Tokens are short-lived (about 1 hour), and access can be revoked instantly by removing an IAM binding.
- The org policy `iam.disableServiceAccountKeyCreation` can be switched on with no impact.
