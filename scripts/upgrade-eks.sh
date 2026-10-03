#!/usr/bin/env bash
# upgrade-eks.sh — Sequential EKS cluster upgrade, one minor version at a time.
#
# Usage:
#   ./scripts/upgrade-eks.sh <env> <target_version>
#
# Examples:
#   ./scripts/upgrade-eks.sh dev 1.37
#   ./scripts/upgrade-eks.sh preprod 1.33
#
# What it does per hop:
#   1. Upgrade EKS control plane
#   2. Wait for cluster ACTIVE
#   3. Upgrade managed node group (rolling)
#   4. Wait for node group ACTIVE
#   5. Update core add-ons (vpc-cni, kube-proxy, coredns)
#   6. Update AWS LBC Helm chart
#   7. Bump kubernetes_version in the tfvars file
#   8. Terraform apply to sync state
#
# Requirements: aws-cli v2, kubectl, helm, terraform ~1.7

set -euo pipefail

# ── Args ──────────────────────────────────────────────────────────────────────
ENV="${1:-}"
TARGET_VERSION="${2:-}"

if [[ -z "${ENV}" || -z "${TARGET_VERSION}" ]]; then
  echo "Usage: $0 <env> <target_version>"
  echo "  env            : dev | preprod | prod"
  echo "  target_version : e.g. 1.37"
  exit 1
fi

# ── Config ────────────────────────────────────────────────────────────────────
CLUSTER_NAME="anycompany-users-${ENV}-cluster"
NODE_GROUP="anycompany-users-${ENV}-nodes"
AWS_REGION="${AWS_REGION:-us-east-1}"
TF_DIR="infrastructure/env"
TFVARS_FILE="${TF_DIR}/environments/${ENV}.tfvars"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-}"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "[$(date '+%H:%M:%S')] $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

wait_cluster_active() {
  log "Waiting for cluster to become ACTIVE..."
  aws eks wait cluster-active --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
  log "Cluster is ACTIVE"
}

wait_nodegroup_active() {
  log "Waiting for node group to become ACTIVE..."
  aws eks wait nodegroup-active \
    --cluster-name "${CLUSTER_NAME}" \
    --nodegroup-name "${NODE_GROUP}" \
    --region "${AWS_REGION}"
  log "Node group is ACTIVE"
}

current_cluster_version() {
  aws eks describe-cluster \
    --name "${CLUSTER_NAME}" \
    --query 'cluster.version' \
    --output text \
    --region "${AWS_REGION}"
}

current_nodegroup_version() {
  aws eks describe-nodegroup \
    --cluster-name "${CLUSTER_NAME}" \
    --nodegroup-name "${NODE_GROUP}" \
    --query 'nodegroup.version' \
    --output text \
    --region "${AWS_REGION}"
}

latest_addon_version() {
  local addon="${1}" k8s_ver="${2}"
  aws eks describe-addon-versions \
    --kubernetes-version "${k8s_ver}" \
    --addon-name "${addon}" \
    --query 'addons[0].addonVersions[0].addonVersion' \
    --output text \
    --region "${AWS_REGION}"
}

update_tfvars_version() {
  local version="${1}"
  sed -i "s/^kubernetes_version = .*/kubernetes_version = \"${version}\"/" "${TFVARS_FILE}"
  log "Updated ${TFVARS_FILE} → kubernetes_version = ${version}"
}

terraform_apply() {
  local version="${1}"
  log "Running terraform apply for version ${version}..."

  EKS_ENDPOINT=$(aws eks describe-cluster --name "${CLUSTER_NAME}" \
    --query 'cluster.endpoint' --output text --region "${AWS_REGION}")
  EKS_CA=$(aws eks describe-cluster --name "${CLUSTER_NAME}" \
    --query 'cluster.certificateAuthority.data' --output text --region "${AWS_REGION}")

  TF_INIT_ARGS="-reconfigure"
  if [[ -n "${TF_STATE_BUCKET}" ]]; then
    TF_INIT_ARGS+=" -backend-config=key=${ENV}/terraform.tfstate"
    TF_INIT_ARGS+=" -backend-config=bucket=${TF_STATE_BUCKET}"
    TF_INIT_ARGS+=" -backend-config=region=${AWS_REGION}"
  fi

  # shellcheck disable=SC2086
  terraform -chdir="${TF_DIR}" init ${TF_INIT_ARGS}

  terraform -chdir="${TF_DIR}" apply \
    -var-file="environments/${ENV}.tfvars" \
    -var="env=${ENV}" \
    -var="kubernetes_version=${version}" \
    -var="eks_cluster_endpoint=${EKS_ENDPOINT}" \
    -var="eks_cluster_ca_cert=${EKS_CA}" \
    -target=aws_eks_cluster.main \
    -target=aws_eks_node_group.main \
    -auto-approve
}

update_addons() {
  local version="${1}"
  log "Updating core add-ons for Kubernetes ${version}..."

  for ADDON in vpc-cni kube-proxy coredns; do
    ADDON_VERSION=$(latest_addon_version "${ADDON}" "${version}")
    if [[ "${ADDON_VERSION}" == "None" || -z "${ADDON_VERSION}" ]]; then
      log "  Skipping ${ADDON} — no version found for k8s ${version}"
      continue
    fi
    log "  Updating ${ADDON} → ${ADDON_VERSION}"
    aws eks update-addon \
      --cluster-name "${CLUSTER_NAME}" \
      --addon-name "${ADDON}" \
      --addon-version "${ADDON_VERSION}" \
      --resolve-conflicts OVERWRITE \
      --region "${AWS_REGION}" >/dev/null
  done
  log "Add-on updates submitted (they apply async)"
}

update_lbc() {
  log "Updating AWS Load Balancer Controller Helm chart..."
  helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
  helm repo update eks
  helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --reuse-values \
    --wait
  log "AWS LBC updated"
}

check_deprecated_apis() {
  local next_version="${1}"
  log "Checking for deprecated API usage before upgrading to ${next_version}..."
  kubectl get --raw /metrics 2>/dev/null \
    | grep 'apiserver_requested_deprecated_apis' \
    | grep -v '^#' \
    | grep 'removed_release="'"${next_version}"'"' \
    && die "Deprecated APIs in use that are removed in ${next_version}. Fix before upgrading." \
    || log "  No blocking deprecated APIs found for ${next_version}"
}

# ── Build upgrade path ────────────────────────────────────────────────────────
CURRENT=$(current_cluster_version)
log "Cluster: ${CLUSTER_NAME}"
log "Current version: ${CURRENT}"
log "Target version:  ${TARGET_VERSION}"

# Parse major.minor
CURRENT_MINOR=$(echo "${CURRENT}" | cut -d. -f2)
TARGET_MINOR=$(echo "${TARGET_VERSION}" | cut -d. -f2)

if [[ "${CURRENT_MINOR}" -ge "${TARGET_MINOR}" ]]; then
  log "Cluster is already at or beyond ${TARGET_VERSION}. Nothing to do."
  exit 0
fi

HOPS=$(( TARGET_MINOR - CURRENT_MINOR ))
log "Upgrade path: ${HOPS} hop(s) required"
echo ""

# Configure kubectl
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"

# ── Sequential upgrade loop ───────────────────────────────────────────────────
for i in $(seq 1 "${HOPS}"); do
  FROM_MINOR=$(( CURRENT_MINOR + i - 1 ))
  TO_MINOR=$(( CURRENT_MINOR + i ))
  FROM_VERSION="1.${FROM_MINOR}"
  TO_VERSION="1.${TO_MINOR}"

  echo ""
  echo "════════════════════════════════════════════════════════════"
  log "Hop ${i}/${HOPS}: ${FROM_VERSION} → ${TO_VERSION}"
  echo "════════════════════════════════════════════════════════════"

  # Pre-flight: check for removed APIs
  check_deprecated_apis "${TO_VERSION}"

  # Step 1 — Upgrade control plane
  log "Upgrading control plane to ${TO_VERSION}..."
  aws eks update-cluster-version \
    --name "${CLUSTER_NAME}" \
    --kubernetes-version "${TO_VERSION}" \
    --region "${AWS_REGION}" >/dev/null
  wait_cluster_active

  # Step 2 — Upgrade node group
  NG_VERSION=$(current_nodegroup_version)
  if [[ "${NG_VERSION}" != "${TO_VERSION}" ]]; then
    log "Upgrading node group to ${TO_VERSION} (rolling, maxUnavailable=1)..."
    aws eks update-nodegroup-version \
      --cluster-name "${CLUSTER_NAME}" \
      --nodegroup-name "${NODE_GROUP}" \
      --kubernetes-version "${TO_VERSION}" \
      --region "${AWS_REGION}" >/dev/null
    wait_nodegroup_active
  else
    log "Node group already at ${TO_VERSION}"
  fi

  # Step 3 — Update add-ons
  update_addons "${TO_VERSION}"

  # Step 4 — Update LBC on final hop only (avoid unnecessary restarts mid-upgrade)
  if [[ "${i}" -eq "${HOPS}" ]]; then
    update_lbc
  fi

  # Step 5 — Sync Terraform state
  update_tfvars_version "${TO_VERSION}"
  terraform_apply "${TO_VERSION}"

  log "Hop ${i}/${HOPS} complete: cluster is now at ${TO_VERSION}"
done

echo ""
echo "════════════════════════════════════════════════════════════"
log "Upgrade complete! Cluster ${CLUSTER_NAME} is now at ${TARGET_VERSION}"
echo "════════════════════════════════════════════════════════════"

# Final verification
kubectl get nodes -o wide
kubectl get pods -n kube-system
