# DevOps - Step-by-step Setup Guide

Diagram: [`diagrams/03-devops-cicd.drawio`](../../diagrams/03-devops-cicd.drawio)
Prerequisites: Phase 0 of the [learning log](../learning-log.md) (tools + `gcloud auth login` + `gcloud auth application-default login`).

Kubernetes resources have one source of truth: the Helm charts in `charts/`. `charts/app` is installed in both clusters; `charts/gateway` is installed in the config cluster. The old `k8s/` directories contain no tracked manifests. Do not apply a second copy of standalone Kubernetes YAML.

## 1. Bootstrap (once, from your laptop)
```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # edit project_id, billing_account
terraform init
terraform plan -out tfplan
terraform apply tfplan
terraform output -raw gh_variable_commands     # copy/paste -> sets GitHub repo variables
```

## 2. Point gcloud at the new project
```bash
export PROJECT_ID=$(terraform output -raw project_id)
gcloud config set project "$PROJECT_ID"
gcloud auth application-default set-quota-project "$PROJECT_ID"
```

## 3. (Optional) Move bootstrap state into the bucket
Add `backend "gcs" { bucket = "<project>-tfstate"  prefix = "bootstrap" }` to `versions.tf`, then run `terraform init -migrate-state`.

## 4. Platform
```bash
cd ../envs/prod
cp terraform.tfvars.example terraform.tfvars   # project_id, ci_apps_sa
terraform init -backend-config="bucket=${PROJECT_ID}-tfstate"
terraform plan -out tfplan
terraform apply tfplan                         # ~20-25 min (clusters + Cloud SQL)
```

## 5. First image build (from a laptop; after this, CI does it)
```bash
gcloud auth configure-docker us-docker.pkg.dev
REG=us-docker.pkg.dev/$PROJECT_ID/apps
BACKUP_REG=us-east1-docker.pkg.dev/$PROJECT_ID/apps-backup
for app in app1 app2; do
  docker build --platform linux/amd64 --build-arg APP=$app --build-arg VERSION=manual-1 -t $REG/$app:manual-1 apps/
  docker push $REG/$app:manual-1
  docker tag $REG/$app:manual-1 $BACKUP_REG/$app:manual-1
  docker push $BACKUP_REG/$app:manual-1
done
```
Binary Authorization starts in `DRYRUN_AUDIT_LOG_ONLY` mode (see tfvars), so these unsigned images are allowed but logged.

## 6. Deploy
```bash
bash scripts/deploy.sh "$PROJECT_ID" manual-1
IP=$(cd terraform/envs/prod && terraform output -raw gateway_ip)
gh variable set GATEWAY_IP --body "$IP"
HOST=$(cd terraform/envs/prod && terraform output -raw gateway_hostname)
curl -sS https://$HOST/app1/        # shows which cluster/region answered
curl -sS https://$HOST/app2/orders  # app2 -> app1 cross-service call; "cache" is hit/miss from Redis
```
`HOST` is `terraform output -raw gateway_hostname` (default `<ip-with-dashes>.nip.io`). The Google-managed certificate can take up to about an hour to turn ACTIVE (`gcloud compute ssl-certificates list`); until then use `curl -k` or HTTP, which only redirects to HTTPS. Port 80 returns a 301 to HTTPS.

To use your own domain, set `domain = "app.example.com"` and `dns_zone_domain = "example.com"` in tfvars, apply, then set the registrar nameservers to `terraform output dns_name_servers`.
The deployment script reads the `net.gke.io/derived-service` annotation from app1's MCS ServiceImport in each cluster and passes the mesh-compatible URL (`http://<derived-service>.app1.svc.cluster.local:8080/app1/items`) to app2. It deploys Helm releases by immutable image digest, not tag.

## 7. Switch on the remaining features
- Set `uptime_host = "<IP>"` and `alert_email` in tfvars, then run `terraform apply` again.
- In GitHub repository Settings > Secrets and variables > Actions, set repository variable `GATEWAY_IP` to the gateway IP and encrypted repository secret `ALERT_EMAIL` to the alert recipient. CI checks both values before planning and refuses to auto-apply plans containing deletions.
- The Terraform workflow validates and plans on pull requests; production apply runs only on `main` through the `prod` environment. The app workflow runs Python tests and Helm lint/render, builds and mirrors immutable images, blocks CRITICAL scan findings, creates Binary Authorization attestations, and deploys by digest. Pull requests do not receive cloud credentials.
- Current production enforces `ENFORCED_BLOCK_AND_AUDIT_LOG`. For a fresh project, keep the initial dry-run mode until CI has produced valid attestations, then set `binauthz_enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"`.
- GitHub: create an environment called `prod` with yourself as a required reviewer.
- Complete Google's email verification link for the Monitoring notification channel before relying on email delivery.

## 8. Grafana Cloud
1. Create a Grafana Cloud stack and install the signed **Google BigQuery** data source plugin.
2. Create a local key for the credential-only service account. Its only permission is to impersonate `grafana-reader`; it has no direct data-reader roles.
   ```bash
   umask 077
   mkdir -p "$HOME/.config/grafana"
   chmod 700 "$HOME/.config/grafana"
   gcloud iam service-accounts keys create "$HOME/.config/grafana/grafana-auth.json" \
     --iam-account="$(terraform -chdir=terraform/envs/prod output -raw grafana_auth_service_account)" \
     --project="$PROJECT_ID"
   chmod 600 "$HOME/.config/grafana/grafana-auth.json"
   ```
   Service-account keys are long-lived credentials. Do not commit, paste, or share this file.
3. In Grafana, add a **Google BigQuery** data source. Select **Google JWT File**, upload `grafana-auth.json`, enable **Service account impersonation**, and set the target to `grafana-reader@$PROJECT_ID.iam.gserviceaccount.com`. Set **Default project** to `$PROJECT_ID`, then click **Save & test**.
4. Add a **Google Cloud Monitoring** data source using the same JWT file and service-account impersonation target. Set the project to `$PROJECT_ID`, click **Save & test**, and use PromQL queries for Managed Prometheus metrics.
5. Import `grafana/dashboards/platform-overview.json`, map `DS_BIGQUERY` to BigQuery and `DS_PROMETHEUS` to Google Cloud Monitoring, then keep the `project` variable default set to `$PROJECT_ID`.
6. The overview dashboard uses BigQuery panels for logs, errors, latency, resources, WAF and cluster traffic, plus Cloud Monitoring PromQL panels for app request rate, 5xx rate and p95 latency. Keep the key active while Grafana Cloud uses it. Delete the local copy after upload; revoke/rotate the GCP key when replacing it in Grafana.

Cloud Service Mesh is managed through Fleet memberships and injects an Envoy sidecar into each app pod. Standalone pricing currently estimates about $0.50 per mesh client per month; at 12 minimum app replicas this is about $6/month, before any custom metrics or scale-out. Confirm current billing terms in Cloud Billing.

Redis cross-region recovery uses Cloud Scheduler to export the regional primary's RDB every 12 hours to a versioned US multi-region bucket. The secondary Redis instance is disabled by default; see the [SRE recovery runbook](../sre/observability-and-dr.md) to provision it and import the latest backup during a regional recovery.

## 9. Teardown
```bash
cd terraform/envs/prod && terraform destroy     # requires deletion_protection=false
cd ../../bootstrap && terraform apply -var project_deletion_policy=DELETE && terraform destroy
```
