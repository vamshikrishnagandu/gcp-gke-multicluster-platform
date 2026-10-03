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

IMAGE_APP1="${REGISTRY}/app1@$(digest_of app1)"
IMAGE_APP2="${REGISTRY}/app2@$(digest_of app2)"
echo "app1 -> ${IMAGE_APP1}"
echo "app2 -> ${IMAGE_APP2}"

render() {
  kubectl kustomize "$1" |
    sed -e "s|PROJECT_ID|${PROJECT_ID}|g" \
        -e "s|IMAGE_APP1|${IMAGE_APP1}|g" \
        -e "s|IMAGE_APP2|${IMAGE_APP2}|g"
}

for entry in "${CLUSTERS[@]}"; do
  name="${entry%%:*}"
  region="${entry##*:}"
  echo "==> ${name} (${region})"
  # --dns-endpoint: IAM-authorised control-plane access, no IP allow-list needed
  gcloud container clusters get-credentials "${name}" --region "${region}" \
    --project "${PROJECT_ID}" --dns-endpoint

  for app in app1 app2; do
    render "${ROOT}/k8s/base/${app}" | kubectl apply -f -
  done

  if [[ "${name}" == "${CONFIG_CLUSTER}" ]]; then
    echo "    config cluster -> applying Gateway"
    render "${ROOT}/k8s/gateway" | kubectl apply -f -
  fi

  for app in app1 app2; do
    kubectl -n "${app}" rollout status "deploy/${app}" --timeout=300s
  done
done

echo "Done. Gateway IP: $(gcloud compute addresses describe platform-gateway-ip --global --project "${PROJECT_ID}" --format='value(address)')"
echo "The global LB takes ~5-10 minutes to program on first deploy."
