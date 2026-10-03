#!/usr/bin/env bash
# teardown.sh — Destroy one environment completely.
#
# Usage:
#   ./scripts/teardown.sh <env> <tf_state_bucket> [aws_region]
#
# Examples:
#   ./scripts/teardown.sh dev     my-tfstate-bucket
#   ./scripts/teardown.sh preprod my-preprod-tfstate-bucket
#   ./scripts/teardown.sh prod    my-prod-tfstate-bucket
#
# Order of operations:
#   1. Delete K8s workloads + TargetGroupBindings (so LBC deregisters pod IPs
#      from ALB target groups before Terraform tries to delete the TGs)
#   2. terraform destroy (removes all AWS resources for the environment)

set -euo pipefail

ENV="${1:-}"
TF_STATE_BUCKET="${2:-}"
AWS_REGION="${3:-us-east-1}"

if [[ -z "${ENV}" || -z "${TF_STATE_BUCKET}" ]]; then
  echo "Usage: $0 <env> <tf_state_bucket> [aws_region]"
  echo "  env             : dev | preprod | prod"
  echo "  tf_state_bucket : S3 bucket holding Terraform state for this env"
  echo "  aws_region      : default us-east-1"
  exit 1
fi

CLUSTER_NAME="anycompany-users-${ENV}-cluster"
NS="anycompany-users-${ENV}"
TF_DIR="infrastructure/env"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ── Step 1: Clean up Kubernetes resources ────────────────────────────────────
log "Configuring kubectl for ${CLUSTER_NAME}..."

if aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" &>/dev/null; then
  aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"

  log "Deleting TargetGroupBindings (so LBC deregisters pod IPs before TG is deleted)..."
  kubectl delete targetgroupbinding --all -n "${NS}" --ignore-not-found

  log "Deleting deployments, services, HPAs..."
  kubectl delete deployment,service,hpa --all -n "${NS}" --ignore-not-found

  log "Waiting 15s for LBC to finish deregistering targets..."
  sleep 15
else
  log "EKS cluster ${CLUSTER_NAME} not found — skipping kubectl cleanup"
fi

# ── Step 2: Terraform destroy ─────────────────────────────────────────────────
log "Initialising Terraform for env=${ENV}..."

terraform -chdir="${TF_DIR}" init -reconfigure \
  -backend-config="key=${ENV}/terraform.tfstate" \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="region=${AWS_REGION}"

EKS_ENDPOINT=$(aws eks describe-cluster --name "${CLUSTER_NAME}" \
  --query 'cluster.endpoint' --output text --region "${AWS_REGION}" 2>/dev/null || echo "")
EKS_CA=$(aws eks describe-cluster --name "${CLUSTER_NAME}" \
  --query 'cluster.certificateAuthority.data' --output text --region "${AWS_REGION}" 2>/dev/null || echo "")

log "Running terraform destroy for env=${ENV}..."
terraform -chdir="${TF_DIR}" destroy \
  -var-file="environments/${ENV}.tfvars" \
  -var="env=${ENV}" \
  -var="eks_cluster_endpoint=${EKS_ENDPOINT}" \
  -var="eks_cluster_ca_cert=${EKS_CA}" \
  -auto-approve

log "Teardown of ${ENV} complete."
