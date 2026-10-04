# ADR 0005: Data-tier access from the apps

## Status
Accepted

## Context
Cloud SQL and Redis were provisioned but unused by the applications, so the brief's "apps can use Cloud SQL or MemoryStore" was not demonstrated.

## Decision
- **app1 -> Cloud SQL:** Cloud SQL Python Connector, private IP, IAM database authentication as `wl-app1`. A Helm post-install/upgrade hook Job runs the schema as `pgadmin` using a dedicated identity (`wl-db-init`) that is the only reader of the admin password, and grants `SELECT` on `catalog.items` to `wl-app1`.
- **app2 -> Redis:** read-through cache of the app1 catalog (30 s TTL) over TLS with AUTH. The AUTH string and CA certificate are Terraform-managed Secret Manager secrets readable only by `wl-app2`.
- Both paths degrade gracefully (static catalog; direct call to app1) and report their state in the response (`items_source`, `cache`).
- Endpoints are looked up by `scripts/deploy.sh` from gcloud, not hard-coded.

## Alternatives rejected
- Database password in the app: avoidable with IAM auth.
- Terraform PostgreSQL provider for grants: the database has no public path; a Job inside the VPC works with the existing network.
- Failing the request when Redis is down: a cache outage should not become an availability outage.

## Consequences
- app1 depends on a cross-region database connection from the other cluster (higher latency; HA primary lives in us-central1).
- The CI deploy identity needs `cloudsql.viewer` and `redis.viewer` to read endpoints.
- Redis restore (cold recovery) must be followed by refreshing the Redis secrets and the `redis.host` value.
