# ADR 0004: HTTPS with a managed certificate and a Cloud Domains domain

## Status
Accepted

## Context
The first deployment answered on a bare IP over HTTP. The brief asks for a global HTTPS load balancer with TLS at the edge and a friendly DNS name.

## Decision
- Register `vamshicloudlab.com` in Cloud Domains with a Terraform-managed public Cloud DNS zone (DNSSEC on) and serve the Gateway at `app.vamshicloudlab.com`.
- Use a Google-managed SSL certificate (`google_compute_managed_ssl_certificate`) attached to the Gateway as a pre-shared certificate (`networking.gke.io/pre-shared-certs`). The certificate name carries a hash of the hostname so a hostname change creates the new certificate before the old one is removed.
- The Gateway has two listeners: HTTPS 443 (app routes) and HTTP 80 (one route that returns a 301 to HTTPS).
- Uptime checks probe HTTPS and validate the certificate.
- `domain` and `dns_zone_domain` are Terraform variables; clearing them falls back to `<ip-with-dashes>.nip.io` without a Cloud DNS zone.

## Consequences
- Certificate provisioning takes minutes to about an hour after DNS resolves; the old hostname's certificate is kept attached until the new one is ACTIVE.
- `deploy.sh` attaches every `platform-gw-*` certificate (comma-separated), so rotation has no downtime. Terraform cannot delete the old certificate until the Gateway stops using it, so a hostname change needs apply, deploy, apply.
- The domain is a billable yearly registration and the registrant email must be verified with ICANN.
