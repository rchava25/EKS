#!/usr/bin/env bash
# Demo: AWS DevOps Agent self-healing scenario
# Simulates a bad users-service deployment, then shows how to trigger the agent
# and view its analysis.
set -euo pipefail

CLUSTER="anycompany-users-dev-cluster"
NAMESPACE="anycompany-users-dev"
REGION="us-east-1"
DEPLOYMENT="users-service"

step() { echo; echo "══════════════════════════════════════════"; echo "  $*"; echo "══════════════════════════════════════════"; }

# ── Prereqs ───────────────────────────────────────────────────────────────────
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" 2>/dev/null || true

AGENT_SPACE_ID=$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
  --query 'cluster.tags' --output json 2>/dev/null || echo "")
# Fetch from Terraform output
AGENT_SPACE_ID=$(cd "$(dirname "$0")/../infrastructure/env" && \
  terraform output -raw devops_agent_space_id 2>/dev/null || echo "")

# ── PHASE 1: Introduce the failure ────────────────────────────────────────────
step "PHASE 1 — Inject failure: wrong DynamoDB table name"

echo "Patching $DEPLOYMENT with incorrect TABLE_NAME env var..."
kubectl set env deployment/$DEPLOYMENT \
  TABLE_NAME="wrong-table-does-not-exist" \
  -n "$NAMESPACE"

echo "Waiting 30s for pods to start crashing..."
sleep 30

step "PHASE 2 — Observe the failure"

echo "--- Pod status ---"
kubectl get pods -n "$NAMESPACE" -l app=users-service

echo ""
echo "--- Recent events ---"
kubectl get events -n "$NAMESPACE" \
  --field-selector reason=BackOff \
  --sort-by='.lastTimestamp' | tail -10

echo ""
echo "--- Pod logs (last 20 lines of crashing pod) ---"
CRASHING_POD=$(kubectl get pods -n "$NAMESPACE" -l app=users-service \
  --field-selector status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
  kubectl get pods -n "$NAMESPACE" -l app=users-service \
  -o jsonpath='{.items[0].metadata.name}')
kubectl logs "$CRASHING_POD" -n "$NAMESPACE" --tail=20 2>&1 || true

echo ""
echo "--- ALB Target Group health ---"
TG_ARN=$(cd "$(dirname "$0")/../infrastructure/env" && \
  terraform output -raw users_tg_arn 2>/dev/null || echo "")
if [[ -n "$TG_ARN" ]]; then
  aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
    --region "$REGION" \
    --query 'TargetHealthDescriptions[*].{Target:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}' \
    --output table
fi

# ── PHASE 3: Trigger the DevOps Agent ─────────────────────────────────────────
step "PHASE 3 — Trigger AWS DevOps Agent for root cause analysis"

if [[ -z "$AGENT_SPACE_ID" ]]; then
  echo "⚠  Could not retrieve agent space ID from Terraform outputs."
  echo "   Run manually:"
  echo "   aws aidevops start-agent-run --agent-space-id <ID> --region $REGION"
else
  echo "Agent Space ID: $AGENT_SPACE_ID"
  echo "Triggering agent run..."
  RUN_ID=$(aws aidevops start-agent-run \
    --agent-space-id "$AGENT_SPACE_ID" \
    --region "$REGION" \
    --query 'agentRunId' --output text 2>/dev/null || echo "")

  if [[ -n "$RUN_ID" ]]; then
    echo "Agent run started: $RUN_ID"
    echo "Polling for analysis (this takes 2-3 minutes)..."
    for i in {1..18}; do
      STATUS=$(aws aidevops get-agent-run \
        --agent-space-id "$AGENT_SPACE_ID" \
        --agent-run-id "$RUN_ID" \
        --region "$REGION" \
        --query 'status' --output text 2>/dev/null || echo "UNKNOWN")
      echo "  [$i/18] Status: $STATUS"
      [[ "$STATUS" == "COMPLETED" || "$STATUS" == "FAILED" ]] && break
      sleep 10
    done

    echo ""
    echo "--- Agent Analysis ---"
    aws aidevops get-agent-run \
      --agent-space-id "$AGENT_SPACE_ID" \
      --agent-run-id "$RUN_ID" \
      --region "$REGION" \
      --output json 2>/dev/null || echo "(View results in the AWS DevOps Agent console)"
  fi
fi

echo ""
echo "Console: https://$REGION.console.aws.amazon.com/devops-agent/home?region=$REGION"

# ── PHASE 4: Remediate ────────────────────────────────────────────────────────
step "PHASE 4 — Remediate: restore correct table name"

TABLE_NAME=$(cd "$(dirname "$0")/../infrastructure/env" && \
  terraform output -raw dynamodb_table_name 2>/dev/null || echo "anycompany-users-dev-users")

echo "Restoring TABLE_NAME=$TABLE_NAME"
kubectl set env deployment/$DEPLOYMENT \
  TABLE_NAME="$TABLE_NAME" \
  -n "$NAMESPACE"

echo "Waiting for rollout to complete..."
kubectl rollout status deployment/$DEPLOYMENT -n "$NAMESPACE" --timeout=3m

step "PHASE 4 — Verify recovery"

echo "--- Pod status ---"
kubectl get pods -n "$NAMESPACE" -l app=users-service

echo ""
echo "--- Target Group health ---"
if [[ -n "$TG_ARN" ]]; then
  sleep 15
  aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
    --region "$REGION" \
    --query 'TargetHealthDescriptions[*].{Target:Target.Id,State:TargetHealth.State}' \
    --output table
fi

echo ""
echo "✓ Scenario complete."
