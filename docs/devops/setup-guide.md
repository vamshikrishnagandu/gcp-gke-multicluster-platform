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
for app in app1 app2; do
  docker build --build-arg APP=$app --build-arg VERSION=manual-1 -t $REG/$app:manual-1 apps/
  docker push $REG/$app:manual-1
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
1. Create a free stack at grafana.com and install the **Google BigQuery** data source plugin.
2. `gcloud iam service-accounts keys create grafana.json --iam-account=grafana-reader@$PROJECT_ID.iam.gserviceaccount.com` (this key is git-ignored; upload it to Grafana, then delete the local file).
3. Import `grafana/dashboards/platform-overview.json` and set the `project` variable.

## 9. Teardown
```bash
cd terraform/envs/prod && terraform destroy     # requires deletion_protection=false
cd ../../bootstrap && terraform apply -var project_deletion_policy=DELETE && terraform destroy
```
