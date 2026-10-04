#!/usr/bin/env bash
# Deploy app1 + app2 to EVERY cluster, and the Gateway to the config cluster only.
# Usage: scripts/deploy.sh <project_id> <image_tag>
#   image_tag = git SHA (CI) or e.g. "manual-1" (laptop)
# Images are referenced by DIGEST (sha256) - Binary Authorization verifies digests, not tags.
set -euo pipefail

PROJECT_ID="${1:?project id}"
TAG="${2:?image tag}"
REGISTRY="us-docker.pkg.dev/${PROJECT_ID}/apps"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# cluster-name:region pairs - must match terraform/envs/prod variable "regions"
CLUSTERS=("gke-usc1:us-central1" "gke-use1:us-east1")
# Config cluster = alphabetically first key in envs/prod "regions": sort(["usc1","use1"]) -> "usc1"
# ('c' < 'e'). Override with CONFIG_CLUSTER=... or read `terraform output -raw config_cluster`.
CONFIG_CLUSTER="${CONFIG_CLUSTER:-gke-usc1}"

digest_of() {
  gcloud artifacts docker images describe "${REGISTRY}/$1:${TAG}" \
    --format='value(image_summary.digest)'
}

image_for() {
  local app="$1"
  local digest
  digest="$(digest_of "$app")"
  printf '%s/%s@%s' "$REGISTRY" "$app" "$digest"
}

# Data-tier endpoints and the TLS certificate are looked up, not hard-coded.
SQL_INSTANCE="${SQL_INSTANCE:-pg-primary-v1}"
REDIS_INSTANCE="${REDIS_INSTANCE:-cache-v1}"
REDIS_REGION="${REDIS_REGION:-us-central1}"
SQL_CONNECTION_NAME="$(gcloud sql instances describe "$SQL_INSTANCE" --project "$PROJECT_ID" --format='value(connectionName)')"
REDIS_HOST="$(gcloud redis instances describe "$REDIS_INSTANCE" --region "$REDIS_REGION" --project "$PROJECT_ID" --format='value(host)')"
REDIS_PORT="$(gcloud redis instances describe "$REDIS_INSTANCE" --region "$REDIS_REGION" --project "$PROJECT_ID" --format='value(port)')"
TLS_CERT_NAME="$(gcloud compute ssl-certificates list --project "$PROJECT_ID" \
  --filter='name~^platform-gw-' --sort-by=~creationTimestamp --limit=1 --format='value(name)')"
for v in SQL_CONNECTION_NAME REDIS_HOST TLS_CERT_NAME; do
  [[ -n "${!v}" ]] || { echo "Could not resolve ${v}; run terraform apply first" >&2; exit 1; }
done

for entry in "${CLUSTERS[@]}"; do
  name="${entry%%:*}"
  region="${entry##*:}"
  echo "==> ${name} (${region})"
  # --dns-endpoint: IAM-authorised control-plane access, no IP allow-list needed
  gcloud container clusters get-credentials "${name}" --region "${region}" \
    --project "${PROJECT_ID}" --dns-endpoint

  for app in app1 app2; do
    helm_args=(upgrade --install "$app" "${ROOT}/charts/app"
      --namespace "$app" --create-namespace
      --take-ownership --force-conflicts
      --set-string "appName=$app"
      --set-string "projectID=$PROJECT_ID"
      --set-string "image=$(image_for "$app")")
    if [[ "$app" == "app1" ]]; then
      helm_args+=(--set-string "db.connectionName=${SQL_CONNECTION_NAME}")
    fi
    if [[ "$app" == "app2" ]]; then
      helm_args+=(--set-string "redis.host=${REDIS_HOST}" --set-string "redis.port=${REDIS_PORT}")
      imported_service="$(kubectl -n app1 get serviceimport app1 \
        -o jsonpath='{.metadata.annotations.net\.gke\.io/derived-service}')"
      if [[ -z "$imported_service" ]]; then
        echo "ServiceImport app1 has no MCS-derived service name in ${name}" >&2
        exit 1
      fi
      helm_args+=(--set-string "app1Url=http://${imported_service}.app1.svc.cluster.local:8080/app1/items")
    fi

    helm "${helm_args[@]}" --wait --timeout 10m
  done

  if [[ "${name}" == "${CONFIG_CLUSTER}" ]]; then
    echo "    config cluster -> upgrading Gateway release"
    helm upgrade --install platform-gateway "${ROOT}/charts/gateway" \
      --namespace gateway-infra --create-namespace \
      --take-ownership --force-conflicts \
      --set-string "tlsCertName=${TLS_CERT_NAME}" \
      --wait --timeout 10m
  fi

  for app in app1 app2; do
    kubectl -n "${app}" rollout status "deploy/${app}" --timeout=300s
  done
done

echo "Done. Gateway IP: $(gcloud compute addresses describe platform-gateway-ip --global --project "${PROJECT_ID}" --format='value(address)')"
echo "HTTPS host: $(gcloud compute ssl-certificates describe "${TLS_CERT_NAME}" --global --project "${PROJECT_ID}" --format='value(managed.domains[0])')"
echo "The global LB takes ~5-10 minutes to program on first deploy; the managed certificate can take up to ~60 minutes to turn ACTIVE."
