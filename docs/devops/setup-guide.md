# DevOps - Step-by-step Setup Guide

Diagram: [`diagrams/03-devops-cicd.drawio`](../../diagrams/03-devops-cicd.drawio)
Prerequisites: Phase 0 of the [learning log](../learning-log.md) (tools + `gcloud auth login` + `gcloud auth application-default login`).

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
curl http://$IP/app1/        # shows which cluster/region answered
curl http://$IP/app2/orders  # app2 -> app1 cross-service call
```

## 7. Switch on the remaining features
- Set `uptime_host = "<IP>"` and `alert_email` in tfvars, then run `terraform apply` again.
- Once CI signs images, set `binauthz_enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"`.
- GitHub: create an environment called `prod` with yourself as a required reviewer.

## 8. Grafana Cloud
1. Create a Grafana Cloud stack and install the signed **Google BigQuery** data source plugin.
2. Create a local key for the credential-only service account. Its only permission is to impersonate `grafana-reader`; it has no direct BigQuery roles.
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
4. Import `grafana/dashboards/platform-overview.json`, map `DS_BIGQUERY` to the BigQuery data source, set the `project` variable to `$PROJECT_ID`, then save with **Update default variable values** enabled.
5. Keep the key active while Grafana Cloud uses it. Delete the local copy after upload; revoke/rotate the GCP key only when replacing it in Grafana.

## 9. Teardown
```bash
cd terraform/envs/prod && terraform destroy     # requires deletion_protection=false
cd ../../bootstrap && terraform apply -var project_deletion_policy=DELETE && terraform destroy
```
