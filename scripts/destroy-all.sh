#!/usr/bin/env bash
# destroy-all.sh — Destroy all environments and shared infrastructure.
#
# Usage:
#   ./scripts/destroy-all.sh <shared_tf_bucket> <dev_tf_bucket> \
#                             <preprod_tf_bucket> <prod_tf_bucket> [aws_region]
#
# Example:
#   ./scripts/destroy-all.sh \
#     anycompany-tfstate-shared \
#     anycompany-tfstate-dev \
#     anycompany-tfstate-preprod \
#     anycompany-tfstate-prod \
#     us-east-1
#
# Destruction order (reverse of creation):
#   prod → preprod → dev → shared VPC/NAT/endpoints

set -euo pipefail

SHARED_BUCKET="${1:-}"
DEV_BUCKET="${2:-}"
PREPROD_BUCKET="${3:-}"
PROD_BUCKET="${4:-}"
AWS_REGION="${5:-us-east-1}"

if [[ -z "${SHARED_BUCKET}" || -z "${DEV_BUCKET}" || -z "${PREPROD_BUCKET}" || -z "${PROD_BUCKET}" ]]; then
  echo "Usage: $0 <shared_bucket> <dev_bucket> <preprod_bucket> <prod_bucket> [aws_region]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo ""; echo "══════════════════════════════════════════════"; echo "[$(date '+%H:%M:%S')] $*"; echo "══════════════════════════════════════════════"; }

# ── Destroy environments in reverse promotion order ───────────────────────────

log "Destroying PROD..."
"${SCRIPT_DIR}/teardown.sh" prod "${PROD_BUCKET}" "${AWS_REGION}"

log "Destroying PREPROD..."
"${SCRIPT_DIR}/teardown.sh" preprod "${PREPROD_BUCKET}" "${AWS_REGION}"

log "Destroying DEV..."
"${SCRIPT_DIR}/teardown.sh" dev "${DEV_BUCKET}" "${AWS_REGION}"

# ── Destroy shared infrastructure (VPC, NAT GWs, VPC endpoints) ───────────────

log "Destroying SHARED infrastructure (VPC, NAT Gateways, VPC Endpoints)..."

terraform -chdir=infrastructure/shared init -reconfigure \
  -backend-config="bucket=${SHARED_BUCKET}" \
  -backend-config="key=shared/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}"

terraform -chdir=infrastructure/shared destroy -auto-approve

log "ALL INFRASTRUCTURE DESTROYED"
echo ""
echo "Remaining manual cleanup (not managed by Terraform):"
echo "  - S3 state buckets: ${SHARED_BUCKET}, ${DEV_BUCKET}, ${PREPROD_BUCKET}, ${PROD_BUCKET}"
echo "  - CloudWatch Log Groups: /aws/lambda/anycompany-users-*"
echo "  - CloudWatch Log Groups: /aws/apigateway/anycompany-users-*"
echo ""
echo "To delete log groups:"
echo "  for env in dev preprod prod; do"
echo "    aws logs delete-log-group --log-group-name /aws/lambda/anycompany-users-\${env}-token-authorizer --region ${AWS_REGION} 2>/dev/null || true"
echo "    aws logs delete-log-group --log-group-name /aws/apigateway/anycompany-users-\${env} --region ${AWS_REGION} 2>/dev/null || true"
echo "  done"
