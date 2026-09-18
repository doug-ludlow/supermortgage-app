#!/usr/bin/env bash
# Creates the Terraform state bucket for one environment's GCP project and prints the exact
# init and apply lines. Safe to re-run. Needs gcloud, authenticated as a project owner
# (`gcloud auth login` and `gcloud auth application-default login`).
#
#   infra/bootstrap.sh [PROJECT_ID] [REGION]      defaults: supermortgage-app-nonprod us-central1
set -euo pipefail

PROJECT_ID="${1:-supermortgage-app-nonprod}"
REGION="${2:-us-central1}"
BUCKET="${PROJECT_ID}-tfstate"
ENVIRONMENT="${PROJECT_ID##*-}" # supermortgage-app-nonprod → nonprod → envs/nonprod.tfvars
TF_DIR="$(cd "$(dirname "$0")/terraform" && pwd)"

if [ ! -f "${TF_DIR}/envs/${ENVIRONMENT}.tfvars" ]; then
  echo "No ${TF_DIR}/envs/${ENVIRONMENT}.tfvars for project ${PROJECT_ID}" >&2
  exit 1
fi

if gcloud storage buckets describe "gs://${BUCKET}" >/dev/null 2>&1; then
  echo "State bucket gs://${BUCKET} already exists"
else
  echo "Creating state bucket gs://${BUCKET} in ${REGION}"
  gcloud storage buckets create "gs://${BUCKET}" \
    --project "${PROJECT_ID}" \
    --location "${REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention
fi

# Versioning keeps every state revision, the way back from a bad apply.
gcloud storage buckets update "gs://${BUCKET}" --versioning >/dev/null
echo "Versioning is on for gs://${BUCKET}"

cat <<LINES

Now run, from the repository root:

  cd ${TF_DIR}
  terraform init -backend-config="bucket=${BUCKET}"
  terraform plan  -var-file=envs/${ENVIRONMENT}.tfvars -var state_bucket=${BUCKET}
  terraform apply -var-file=envs/${ENVIRONMENT}.tfvars -var state_bucket=${BUCKET}

LINES
