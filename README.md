# AnyCompany Users Service — EKS Best-Practices Boilerplate

A production-grade EKS boilerplate covering seven modern design patterns:
Auto Mode compute, event-driven autoscaling (KEDA), secrets management (ESO),
resource right-sizing (VPA), distributed tracing (ADOT/X-Ray), policy enforcement
(Kyverno), and optimised VPC networking (Interface Endpoints).

Use this as a starting point for any new EKS service.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Design Patterns & Trade-offs](#design-patterns--trade-offs)
- [Technology Stack](#technology-stack)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Manual Deployment Guide](#manual-deployment-guide)
- [CI/CD Pipeline](#cicd-pipeline)
- [API Reference](#api-reference)
- [Troubleshooting Guide](#troubleshooting-guide)

---

## Architecture Overview

```
─── REQUEST PATH ────────────────────────────────────────────────────────────
Internet
    │
    ▼
Amazon API Gateway (REST)        ← Public HTTPS endpoint
    │   Lambda Token Authorizer  ← JWT validation via Cognito JWKS
    │
    │  VPC Link (private tunnel)
    ▼
Internal ALB  (Terraform-managed, private subnets)
  /auth/*  ──► login-service pods  (EKS Auto Mode)
  /users/* ──► users-service pods  (EKS Auto Mode)
                    ▲                          ▲
           TargetGroupBinding         TargetGroupBinding
           (built-in LBC registers pod IPs automatically)

─── SECRETS PATH ────────────────────────────────────────────────────────────
AWS Secrets Manager  ──► External Secrets Operator ──► K8s Secret ──► pod env

─── OBSERVABILITY PATH ──────────────────────────────────────────────────────
pod → OTEL SDK → ADOT sidecar collector → AWS X-Ray (traces)
                                        → CloudWatch (metrics)

─── SHARED BACKEND ──────────────────────────────────────────────────────────
Amazon DynamoDB          ← Users table (PAY_PER_REQUEST)
Amazon Cognito           ← Auth / token issuance
Amazon ECR               ← Container image registry (via VPC Interface Endpoint)
Amazon SQS               ← Event queue for async scaling (KEDA SQS trigger)
```

### Per-Environment Isolation

| Resource | dev | preprod | prod |
|---|---|---|---|
| EKS cluster (Auto Mode) | anycompany-users-dev-cluster | anycompany-users-preprod-cluster | anycompany-users-prod-cluster |
| EKS version | 1.35 | 1.37 | 1.37 |
| DynamoDB table | anycompany-users-dev-users | anycompany-users-preprod-users | anycompany-users-prod-users |
| Secrets Manager | anycompany-users-dev-* | anycompany-users-preprod-* | anycompany-users-prod-* |
| SQS queue | anycompany-users-dev-users-requests | — | — |

---

## Design Patterns & Trade-offs

### Pattern 1 — EKS Auto Mode (Compute)

**What it replaces:** `aws_eks_node_group` + Helm LBC + `eks-pod-identity-agent` addon

| Factor | Managed Node Group | EKS Auto Mode (current) |
|---|---|---|
| Node provisioning | You define instance type + size | AWS Karpenter picks right size per workload |
| Node patching | Manual — update AMI in node group | AWS patches automatically in maintenance window |
| LBC | Helm release + IAM role required | Built-in (`elastic_load_balancing.enabled = true`) |
| Pod Identity | Addon install required | Built-in |
| Scale speed | 3-5 min (node group ASG) | ~60s (Karpenter direct) |
| Cost surcharge | None | +$0.003/vCPU/hr |
| Instance control | Exact type pinned | NodePool config (family, arch, capacity type) |

**How to configure NodePool** (custom compute requirements):
```yaml
apiVersion: karpenter.k8s.aws/v1
kind: NodePool
metadata:
  name: custom
spec:
  template:
    spec:
      requirements:
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["spot", "on-demand"]
      - key: node.kubernetes.io/instance-type
        operator: In
        values: ["t3.medium", "t3.large", "m5.large"]
```

---

### Pattern 2 — External Secrets Operator (Secrets)

**What it replaces:** Plain-text env vars in Deployment manifests / K8s Secrets in git

| Factor | Env vars in Deployment | ESO + Secrets Manager (current) |
|---|---|---|
| Visibility | `kubectl describe pod` shows values | K8s Secret exists but values are base64 only |
| Rotation | Requires pod restart + redeploy | ESO re-syncs every `refreshInterval` (1h) |
| Audit | No trail | CloudTrail logs every `GetSecretValue` |
| Git safety | Risk of committing secrets | Secrets never in git |
| Drift detection | Manual | ESO reports sync failures as K8s events |

**Flow:**
```
Secrets Manager secret  →(ESO polls every 1h)→  K8s Secret  →(envFrom)→  pod
```

**To rotate a secret:** Update the value in Secrets Manager. ESO syncs within `refreshInterval`. No pod restart needed unless you set `reloadDeploymentOnChange: true`.

---

### Pattern 3 — KEDA (Autoscaling)

**What it replaces:** HPA (CPU/memory only)

| Factor | HPA | KEDA ScaledObject (current) |
|---|---|---|
| Trigger types | CPU, memory | CPU, memory, SQS, DynamoDB, Prometheus, cron, 60+ others |
| Scale to zero | No (min 1) | Yes (SQS trigger with `minReplicaCount: 0`) |
| Event-driven | No — lags behind traffic | Yes — reacts to queue depth before CPU rises |
| Resource | `HorizontalPodAutoscaler` | `ScaledObject` CRD (KEDA creates internal HPA) |

**Two modes provided:**
- `k8s/users-scaledobject.yaml` — CPU 50% trigger (HTTP workloads)
- `k8s/users-scaledobject-sqs.yaml` — SQS queue depth trigger (async workloads, scales to 0)

---

### Pattern 4 — VPA Recommendation Mode (Right-sizing)

**What it does:** Observes actual pod CPU/memory usage over time and writes recommendations to the VPA status field.

```bash
# View recommendations after ~24h of traffic
kubectl get vpa users-service-vpa -n anycompany-users-dev \
  -o jsonpath='{.status.recommendation.containerRecommendations}' | python3 -m json.tool
```

| `updateMode` | Behaviour | Risk |
|---|---|---|
| `Off` (current) | Recommendation only — never touches pods | Zero |
| `Initial` | Sets requests on new pods, never evicts | Low |
| `Auto` | Evicts pods to apply updated requests | Medium — avoid with stateful workloads |

Start with `Off`, review recommendations for a week, then manually apply to `requests` in the Deployment.

---

### Pattern 5 — ADOT + OpenTelemetry (Tracing)

**What it adds:** Distributed traces from API Gateway → Lambda Authorizer → ALB → pod → DynamoDB, forwarded to AWS X-Ray.

**Architecture:**
```
FastAPI app  →(OTLP gRPC localhost:4317)→  ADOT sidecar collector  →  AWS X-Ray
                                                                     →  CloudWatch Metrics
```

**Annotation to inject ADOT sidecar** into any pod:
```yaml
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-python: "true"
```

**Env vars controlling tracing:**
```yaml
env:
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: "http://localhost:4317"
- name: OTEL_SDK_DISABLED
  value: "false"   # set "true" to disable tracing without code change
```

---

### Pattern 6 — Kyverno (Policy Enforcement)

**Policies in `k8s/kyverno-policies.yaml`:**

| Policy | Mode | Rule |
|---|---|---|
| `require-resource-limits` | Audit | All containers must set CPU + memory limits |
| `disallow-root-user` | Audit | `runAsNonRoot: true` required |
| `require-labels` | Audit | `app` and `version` labels required on pods |
| `disallow-privileged-containers` | **Enforce** | `privileged: false` required |
| `require-readiness-probe` | Audit | All containers must define a `readinessProbe` |

**Check violations:**
```bash
kubectl get policyreport -A
kubectl describe clusterpolicyreport
```

**Promote to Enforce** once teams are aware: change `validationFailureAction: Audit` → `Enforce`.

---

### Pattern 7 — VPC Interface Endpoints (Networking)

**What it adds:** Private routes for ECR, STS, and Secrets Manager traffic — eliminates NAT gateway cost for these high-volume flows.

| Endpoint | Traffic eliminated from NAT | Monthly savings (est.) |
|---|---|---|
| `ecr.dkr` | Docker layer pulls (~60-80% of NAT egress) | ~$15-40 per cluster |
| `ecr.api` | ECR API calls | Minimal |
| `sts` | Pod Identity token refreshes (every 15min per pod) | Small |
| `secretsmanager` | ESO polls (hourly per secret) | Minimal |

**Total per-endpoint cost:** ~$7.30/mo each (730hrs × $0.01/hr). Break-even at ~$7.30/mo NAT savings per endpoint — ECR endpoints typically pay for themselves within the first week on a busy cluster.

---

## Technology Stack

| Component | Technology | Version |
|---|---|---|
| IaC | Terraform | ~1.7 |
| Language | Python | 3.10 |
| Compute | Amazon EKS Auto Mode | 1.35 (dev) / 1.37 (preprod/prod) |
| Node provisioning | Karpenter (built-in Auto Mode) | — |
| Database | Amazon DynamoDB | on-demand |
| API | Amazon API Gateway REST (v1) | — |
| Auth | Amazon Cognito + Lambda Authorizer | — |
| Load Balancer | AWS ALB (built-in Auto Mode LBC) | — |
| Container Registry | Amazon ECR | via VPC Interface Endpoint |
| Autoscaling | KEDA ScaledObject | 2.16.0 (Helm) — CPU + SQS triggers |
| IAM for pods | EKS Pod Identity | built-in Auto Mode |
| Cluster access | EKS Access Entries API | API-only mode |
| Secrets | External Secrets Operator + Secrets Manager | ESO 0.10.3 |
| Right-sizing | VPA (recommendation mode) | 4.4.6 |
| Tracing | ADOT + OpenTelemetry + AWS X-Ray | EKS addon |
| Policy engine | Kyverno | 3.2.7 |
| Networking | NAT GW + VPC Gateway Endpoints (S3, DynamoDB) + Interface Endpoints (ECR, STS, SM) | — |

---

## Repository Structure

```
.
├── .github/workflows/deploy.yml     # CI/CD — builds, deploys, promotes
├── infrastructure/
│   ├── shared/                      # VPC, NAT GW, Interface Endpoints, GitHub OIDC
│   │   ├── vpc.tf                   # VPC + subnets + NAT + Gateway/Interface endpoints
│   │   ├── github-oidc.tf           # OIDC + deploy role
│   │   └── variables.tf
│   └── env/                         # Per-environment stack
│       ├── eks.tf                   # EKS Auto Mode cluster + access entries
│       ├── iam.tf                   # Pod Identity roles (login, users)
│       ├── lbc.tf                   # (built-in Auto Mode — no Helm needed)
│       ├── keda.tf                  # KEDA Helm release
│       ├── eso.tf                   # External Secrets Operator + Pod Identity role
│       ├── secrets.tf               # Secrets Manager secrets for app config
│       ├── sqs.tf                   # SQS queue + DLQ + KEDA IAM role
│       ├── vpa.tf                   # Vertical Pod Autoscaler (recommendation mode)
│       ├── adot.tf                  # ADOT EKS addon + IAM role (X-Ray + CloudWatch)
│       ├── kyverno.tf               # Kyverno policy engine
│       ├── devops-agent.tf          # (optional) AWS DevOps Agent — delete if not needed
│       ├── alb.tf                   # ALB + Target Groups + Listener Rules
│       ├── api-gateway.tf           # API Gateway + OpenAPI + Lambda integration
│       ├── cognito.tf               # Cognito User Pool + App Client
│       ├── dynamodb.tf              # DynamoDB users table
│       ├── ecr.tf                   # ECR repos
│       ├── lambda-authorizer.tf     # Lambda token authorizer
│       ├── k8s-infra.tf             # K8s namespaces, ServiceAccounts, NetworkPolicy
│       ├── vpc-link.tf              # VPC Link V2
│       ├── provider.tf              # aws, awscc, kubernetes, helm, time providers
│       ├── variables.tf             # All input variables incl. eks_admin_iam_arns
│       └── environments/
│           ├── dev.tfvars
│           ├── preprod.tfvars
│           └── prod.tfvars
├── k8s/
│   ├── login-deployment.yaml        # Login Deployment (IMAGE_TAG placeholder)
│   ├── login-service.yaml           # Login Service (NodePort)
│   ├── login-tgb.yaml               # Login TargetGroupBinding
│   ├── login-scaledobject.yaml      # KEDA CPU ScaledObject — login (min:2 max:5)
│   ├── login-service-vpa.yaml       # VPA for login-service (recommendation mode)  ← NEW
│   ├── users-deployment.yaml        # Users Deployment
│   ├── users-service.yaml           # Users Service (NodePort)
│   ├── users-tgb.yaml               # Users TargetGroupBinding
│   ├── users-scaledobject.yaml      # KEDA CPU ScaledObject — users (min:2 max:5)
│   ├── users-scaledobject-sqs.yaml  # KEDA SQS ScaledObject — async (min:0 max:10) ← NEW
│   ├── vpa-users.yaml               # VPA for users-service                         ← NEW
│   ├── vpa-login.yaml               # VPA for login-service                         ← NEW
│   ├── cluster-secret-store.yaml    # ESO ClusterSecretStore (AWS_REGION placeholder)← NEW
│   ├── external-secret-users.yaml   # ExternalSecret → users-service-secrets         ← NEW
│   ├── external-secret-login.yaml   # ExternalSecret → login-service-secrets         ← NEW
│   ├── kyverno-policies.yaml        # Kyverno ClusterPolicies (5 rules, Audit mode)  ← NEW
│   └── adot-collector.yaml          # OpenTelemetryCollector CR (sidecar mode)       ← NEW
├── scripts/
│   ├── upgrade-eks.sh               # Sequential EKS upgrade (one minor version)
│   ├── teardown.sh                  # Drain K8s then terraform destroy
│   └── destroy-all.sh               # Full teardown: prod → preprod → dev → shared
└── src/
    ├── login/                       # FastAPI login service (OTEL instrumented)
    ├── users/                       # FastAPI users service (OTEL instrumented)
    └── authorizer/                  # Lambda token authorizer
```

---

## Prerequisites

```bash
terraform -version   # ~1.7
aws --version        # v2
kubectl version --client
helm version
docker --version
python3 --version    # 3.10+
```

---

## Manual Deployment Guide

### Step 1 — Shared infrastructure (one-time)

```bash
cd infrastructure/shared
terraform init
terraform apply
```

This creates: VPC, subnets, NAT gateway, VPC endpoints (Gateway + Interface), GitHub OIDC provider.

### Step 2 — Environment variables

```bash
export ENV=dev
export AWS_REGION=us-east-1
export TF_DIR=infrastructure/env
export TF_STATE_BUCKET=anycompany-users-tfstate-ACCOUNT_ID
```

### Step 3 — Terraform Phase 1: EKS cluster

```bash
cd ${TF_DIR}
terraform init -reconfigure \
  -backend-config="key=${ENV}/terraform.tfstate" \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="region=${AWS_REGION}"

EKS_ENDPOINT=$(aws eks describe-cluster --name "anycompany-users-${ENV}-cluster" \
  --query 'cluster.endpoint' --output text 2>/dev/null || echo "")
EKS_CA=$(aws eks describe-cluster --name "anycompany-users-${ENV}-cluster" \
  --query 'cluster.certificateAuthority.data' --output text 2>/dev/null || echo "")

terraform apply \
  -var-file=environments/${ENV}.tfvars \
  -var="eks_cluster_endpoint=${EKS_ENDPOINT}" \
  -var="eks_cluster_ca_cert=${EKS_CA}" \
  -target=aws_iam_role.eks_cluster \
  -target=aws_iam_role.eks_nodes \
  -target=aws_eks_cluster.main \
  -auto-approve
```

### Step 4 — Grant kubectl access (first deploy only)

```bash
aws sts get-caller-identity --query Arn --output text
# Strip session suffix to get role ARN, then:

aws eks create-access-entry \
  --cluster-name "anycompany-users-${ENV}-cluster" \
  --principal-arn arn:aws:iam::ACCOUNT_ID:role/YOUR_ROLE \
  --type STANDARD

aws eks associate-access-policy \
  --cluster-name "anycompany-users-${ENV}-cluster" \
  --principal-arn arn:aws:iam::ACCOUNT_ID:role/YOUR_ROLE \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

### Step 5 — Terraform Phase 2: full apply

```bash
EKS_ENDPOINT=$(aws eks describe-cluster --name "anycompany-users-${ENV}-cluster" \
  --query 'cluster.endpoint' --output text)
EKS_CA=$(aws eks describe-cluster --name "anycompany-users-${ENV}-cluster" \
  --query 'cluster.certificateAuthority.data' --output text)

terraform apply \
  -var-file=environments/${ENV}.tfvars \
  -var="eks_cluster_endpoint=${EKS_ENDPOINT}" \
  -var="eks_cluster_ca_cert=${EKS_CA}" \
  -auto-approve
cd -
```

> Phase 2 installs KEDA, ESO, VPA, ADOT, and Kyverno via Helm. Order is managed by `depends_on` chains.

### Step 6 — Configure kubectl + deploy app

```bash
aws eks update-kubeconfig --name "anycompany-users-${ENV}-cluster" --region ${AWS_REGION}

IMAGE_TAG=$(git rev-parse --short=8 HEAD)
NS="anycompany-users-${ENV}"

# Apply manifests (pipeline does this automatically)
kubectl apply -n "${NS}" -f k8s/vpa-users.yaml
kubectl apply -n "${NS}" -f k8s/vpa-login.yaml
kubectl apply -f k8s/kyverno-policies.yaml

# View VPA recommendations after 24h
kubectl get vpa -n "${NS}" -o yaml
```

---

## CI/CD Pipeline

| Job | Description |
|---|---|
| `env-config` | Resolve env + tfvars from branch/PR |
| `infra` | Phase 1: EKS cluster → Phase 2: everything else (KEDA, ESO, VPA, ADOT, Kyverno) |
| `app` | Tests → ECR build → EKS deploy → TGBs → ExternalSecrets → VPA → Kyverno policies |
| `promote-preprod` | Manual gate → same image to preprod |
| `promote-prod` | Manual gate → same image to prod |
| `teardown-mr` | `terraform destroy` ephemeral MR env |

### Required Secrets

| Secret | Description |
|---|---|
| `NONPROD_DEPLOY_ROLE_ARN` | IAM role for dev (needs CloudControl API + ESO/SQS/SM permissions) |
| `TF_STATE_BUCKET` | S3 bucket for dev state |
| `PREPROD_DEPLOY_ROLE_ARN` | IAM role for preprod (optional) |
| `PROD_DEPLOY_ROLE_ARN` | IAM role for prod (optional) |

---

## API Reference

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/auth/login` | None | Login, returns tokens |
| POST | `/auth/refresh` | None | Refresh access token |
| POST | `/auth/logout` | None | Invalidate refresh token |
| GET | `/users` | Bearer | List users |
| POST | `/users` | Bearer | Create user |
| GET | `/users/{id}` | Bearer | Get user |
| PUT | `/users/{id}` | Bearer | Update user |
| DELETE | `/users/{id}` | Bearer | Delete user |

---

## Troubleshooting Guide

### ESO sync failing — ExternalSecret status shows `SecretSyncedError`

```bash
kubectl describe externalsecret users-service-secrets -n anycompany-users-dev
# Look for: "could not get secret"
```

**Common causes:**
1. ESO Pod Identity association not yet propagated — wait 30s and retry
2. Secret name mismatch — verify `aws secretsmanager list-secrets`
3. Missing Interface Endpoint for secretsmanager — check `aws ec2 describe-vpc-endpoints`

---

### VPA shows no recommendations

VPA needs ~24h of load data before it has enough samples:
```bash
kubectl describe vpa users-service-vpa -n anycompany-users-dev | grep -A20 "Recommendation"
```

If `Recommendation` is empty, VPA recommender may not be running:
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=vpa
```

---

### Kyverno blocking pods — `admission webhook denied`

```bash
# See which policy blocked it
kubectl get events -n anycompany-users-dev --field-selector reason=PolicyViolation
# Temporarily exclude a namespace from a policy
kubectl label namespace anycompany-users-dev kyverno.io/exclude=true
```

Policies in `Audit` mode report violations but don't block. Only `disallow-privileged-containers` is in `Enforce` mode.

---

### No traces in X-Ray

1. Check ADOT addon is active: `aws eks describe-addon --cluster-name ... --addon-name adot`
2. Check pod has sidecar: `kubectl get pod <pod> -o jsonpath='{.spec.containers[*].name}'`
3. Verify `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317` env var is set
4. Check ADOT IAM role has `AWSXRayDaemonWriteAccess`: `aws iam list-attached-role-policies --role-name anycompany-users-dev-adot-role`

---

### EKS Auto Mode — nodes not scaling up

Auto Mode uses Karpenter internally. Check Karpenter events:
```bash
kubectl get events -A --field-selector reason=ProvisioningFailed
kubectl describe nodeclaim   # lists Karpenter NodeClaims
```

If pods are `Pending` due to insufficient resources:
```bash
kubectl describe pod <pending-pod> | grep -A5 Events
# "0/2 nodes available" → Karpenter is provisioning a new node (~60s)
```

---

### KEDA SQS scaler not triggering

```bash
# Check ScaledObject status
kubectl describe scaledobject users-service-sqs-scaledobject -n anycompany-users-dev

# Verify KEDA can read the queue
kubectl logs -n keda -l app=keda-operator --tail=50 | grep -i sqs

# Check queue depth manually
aws sqs get-queue-attributes \
  --queue-url $(terraform output -raw users_requests_queue_url) \
  --attribute-names ApproximateNumberOfMessages
```

---

### General diagnostics

```bash
# Pod status
kubectl get pods -n anycompany-users-dev

# Kyverno policy violations
kubectl get policyreport -n anycompany-users-dev

# ESO sync status
kubectl get externalsecret -n anycompany-users-dev

# VPA recommendations
kubectl get vpa -n anycompany-users-dev

# KEDA ScaledObjects
kubectl get scaledobject -n anycompany-users-dev

# X-Ray traces (last 1h)
aws xray get-service-graph --start-time $(date -d '-1 hour' +%s) --end-time $(date +%s) --region us-east-1

# EKS Auto Mode node status
kubectl get nodeclaims
kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type
```
