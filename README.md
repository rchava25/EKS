# AnyCompany E-Commerce Platform — ECS Fargate

A production-grade serverless e-commerce backend built on **ECS Fargate** with JWT-based
authentication, event-driven order processing, full-text search, and Redis caching.
All infrastructure is defined in Terraform and deployed to AWS.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Services](#services)
- [Technology Stack](#technology-stack)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Manual Deployment Guide](#manual-deployment-guide)
- [Testing the Flow](#testing-the-flow)
- [CI/CD Pipeline](#cicd-pipeline)
- [Per-Environment Configuration](#per-environment-configuration)
- [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
─── REQUEST PATH ──────────────────────────────────────────────────────────────
Internet
    │
    ▼
Amazon API Gateway (REST v1)         ← Public HTTPS endpoint
    │   Lambda Token Authorizer       ← JWT validation via Cognito JWKS
    │
    │  VPC Link (private tunnel)
    ▼
Internal ALB  (private subnets)
  /auth/*      ──► login-service     (Cognito auth — issues JWT)
  /users/*     ──► users-service     (CRUD users)
  /products/*  ──► browse-service    (product catalog + Redis cache)
  /search/*    ──► search-service    (full-text via OpenSearch)
  /orders/*    ──► payment-service   (order creation + SQS publish)
  /shipping/*  ──► shipping-service  (shipment tracking)
         │
         │   All containers: ECS Fargate (FARGATE + FARGATE_SPOT)
         │   Private subnets → VPC Endpoints (no NAT Gateway)

─── ORDER EVENT FLOW ──────────────────────────────────────────────────────────
POST /orders
    │
    ▼
payment-service  ──► DynamoDB (orders table)
    │
    ├──► SQS: anycompany-users-dev-payment-events   (payment processing)
    │
    └──► SQS: anycompany-users-dev-shipping-dispatch
              │
              ▼
         shipping-service  (SQS long-poll daemon thread)
              │
              ▼
         DynamoDB (shipments table) + mock tracking number

─── SECRETS PATH ──────────────────────────────────────────────────────────────
Secrets Manager ──► ECS task (valueFrom injection) ──► env vars in container

─── CACHING PATH ──────────────────────────────────────────────────────────────
GET /products/{id}
    │
    ├── Redis HIT  → return cached product (ElastiCache Redis 7)
    └── Redis MISS → DynamoDB → cache 5 min → return

─── SEARCH PATH ───────────────────────────────────────────────────────────────
GET /search?q=...
    │
    ▼
search-service ──► OpenSearch (multi_match on name + description + category)
```

### Network Isolation

All ECS tasks run in **private subnets**. Connectivity to AWS services is via VPC
endpoints — no NAT Gateway required:

| Endpoint | Type | Purpose |
|---|---|---|
| `ecr.dkr` / `ecr.api` | Interface | Pull container images |
| `secretsmanager` | Interface | Fetch runtime secrets |
| `logs` | Interface | CloudWatch log delivery |
| `sts` | Interface | IAM role assumption |
| `s3` | Gateway | ECR image layers |

---

## Services

| Service | Port | Path prefix | Key dependencies |
|---|---|---|---|
| **login-service** | 8080 | `/auth` | Cognito |
| **users-service** | 8080 | `/users` | DynamoDB users table |
| **browse-service** | 8080 | `/products` | DynamoDB products table, ElastiCache Redis |
| **search-service** | 8080 | `/search` | OpenSearch |
| **payment-service** | 8080 | `/orders` | DynamoDB orders table, SQS payment-events + shipping-dispatch |
| **shipping-service** | 8080 | `/shipping` | DynamoDB shipments table, SQS shipping-dispatch (consumer) |

---

## Technology Stack

| Layer | Technology |
|---|---|
| IaC | Terraform |
| Language | Python 3.10 / FastAPI + uvicorn |
| Compute | ECS Fargate (FARGATE + FARGATE_SPOT) |
| Auth | Amazon Cognito + Lambda Token Authorizer |
| Database | Amazon DynamoDB (on-demand) |
| Search | Amazon OpenSearch 2.11 (VPC) |
| Cache | ElastiCache Redis 7 (cache.t3.micro) |
| Messaging | Amazon SQS (standard queues) |
| API | Amazon API Gateway REST v1 + VPC Link |
| Registry | Amazon ECR |
| Secrets | AWS Secrets Manager |
| Logs | Amazon CloudWatch Logs |

---

## Repository Structure

```
.
├── infrastructure/env/          # Terraform — all AWS resources
│   ├── environments/
│   │   ├── dev.tfvars
│   │   ├── preprod.tfvars
│   │   └── prod.tfvars
│   ├── alb.tf                   # Internal ALB + ECS security group
│   ├── api-gateway.tf           # API Gateway + VPC Link
│   ├── cognito.tf               # Cognito User Pool + App Client
│   ├── dynamodb.tf              # users / products / orders / shipments tables
│   ├── ecr.tf                   # ECR repositories
│   ├── ecs.tf                   # Cluster, task definitions, services, autoscaling
│   ├── elasticache.tf           # Redis cluster
│   ├── iam.tf                   # Service roles
│   ├── lambda-authorizer.tf     # JWT token authorizer Lambda
│   ├── opensearch.tf            # OpenSearch domain + SLR
│   ├── secrets.tf               # Secrets Manager entries
│   ├── sqs.tf                   # SQS queues
│   ├── vpc.tf                   # Dedicated VPC (preprod/prod only)
│   ├── vpc-endpoints.tf         # VPC endpoints (all envs)
│   └── vpc-link.tf              # NLB for API Gateway VPC Link
├── src/
│   ├── authorizer/              # Lambda JWT authorizer
│   ├── login/                   # Auth service (Cognito)
│   ├── users/                   # User CRUD service
│   ├── browse/                  # Product catalog + caching
│   ├── search/                  # Full-text search
│   ├── payment/                 # Order creation + SQS
│   └── shipping/                # Shipment tracking + SQS consumer
├── tests/unit/                  # pytest + moto
└── .github/workflows/deploy.yml # CI/CD pipeline
```

---

## Prerequisites

- AWS CLI v2 configured (`aws configure` or instance role)
- Terraform >= 1.6
- Docker (for building images)
- Python 3.10+ with `pytest` and `moto` (for tests)

```bash
pip install pytest moto boto3
```

---

## Manual Deployment Guide

### 1. Bootstrap Terraform backend

```bash
aws s3 mb s3://anycompany-users-tfstate --region us-east-1
aws dynamodb create-table \
  --table-name anycompany-users-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 2. Apply infrastructure

```bash
cd infrastructure/env
terraform init
terraform apply -var-file=environments/dev.tfvars
```

### 3. Authenticate Docker to ECR

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin \
    ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com
```

### 4. Build and push all images

```bash
IMAGE_TAG="manual-$(date +%Y%m%d)"

for SVC in login users browse search payment shipping; do
  REPO_MAP=(
    [login]="anycompany-login-service"
    [users]="anycompany-users-service"
    [browse]="anycompany-browse-service"
    [search]="anycompany-search-service"
    [payment]="anycompany-payment-service"
    [shipping]="anycompany-shipping-service"
  )
  REPO="${REPO_MAP[$SVC]}"
  docker build -t ${REPO}:${IMAGE_TAG} src/${SVC}/
  docker tag  ${REPO}:${IMAGE_TAG} \
    ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO}:${IMAGE_TAG}
  docker push \
    ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO}:${IMAGE_TAG}
done
```

### 5. Deploy to ECS

```bash
CLUSTER="anycompany-users-dev-cluster"
TMPFILE=$(mktemp /tmp/task-def.XXXXXX.json)

declare -A SERVICES=(
  [login]="anycompany-login-service"
  [users]="anycompany-users-service"
  [browse]="anycompany-browse-service"
  [search]="anycompany-search-service"
  [payment]="anycompany-payment-service"
  [shipping]="anycompany-shipping-service"
)

for SVC_KEY in "${!SERVICES[@]}"; do
  REPO="${SERVICES[$SVC_KEY]}"
  FAMILY="anycompany-users-dev-${SVC_KEY}-service"
  SERVICE="anycompany-users-dev-${SVC_KEY}"
  NEW_IMAGE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO}:${IMAGE_TAG}"

  aws ecs describe-task-definition \
    --task-definition "${FAMILY}" --region "${REGION}" \
    --query 'taskDefinition' --output json > "${TMPFILE}"

  python3 -c "
import json
with open('${TMPFILE}') as f: d = json.load(f)
for k in ['taskDefinitionArn','revision','status','requiresAttributes',
          'compatibilities','registeredAt','registeredBy']:
    d.pop(k, None)
d['containerDefinitions'][0]['image'] = '${NEW_IMAGE}'
with open('${TMPFILE}','w') as f: json.dump(d, f)
"

  NEW_ARN=$(aws ecs register-task-definition \
    --cli-input-json "file://${TMPFILE}" --region "${REGION}" \
    --query 'taskDefinition.taskDefinitionArn' --output text)

  aws ecs update-service \
    --cluster "${CLUSTER}" --service "${SERVICE}" \
    --task-definition "${NEW_ARN}" --region "${REGION}" --no-cli-pager
done

aws ecs wait services-stable \
  --cluster "${CLUSTER}" --region "${REGION}" \
  --services $(for k in "${!SERVICES[@]}"; do echo "anycompany-users-dev-${k}"; done)

rm -f "${TMPFILE}"
echo "All services stable."
```

---

## Testing the Flow

Get the API Gateway URL first:

```bash
API=$(terraform -chdir=infrastructure/env output -raw api_gateway_invoke_url)
# e.g. https://gwehq97ph4.execute-api.us-east-1.amazonaws.com/v1
CLIENT_ID=$(terraform -chdir=infrastructure/env output -raw cognito_app_client_id)
POOL_ID=$(terraform -chdir=infrastructure/env output -raw cognito_user_pool_id)
```

### Step 1 — Create a Cognito user and get a JWT

```bash
# Create user in Cognito (one-time setup)
aws cognito-idp admin-create-user \
  --user-pool-id "${POOL_ID}" \
  --username test@example.com \
  --temporary-password "Temp1234!" \
  --region us-east-1

# Set permanent password
aws cognito-idp admin-set-user-password \
  --user-pool-id "${POOL_ID}" \
  --username test@example.com \
  --password "MyPassword1!" \
  --permanent \
  --region us-east-1

# Login to get JWT
TOKEN=$(curl -s -X POST "${API}/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"MyPassword1!"}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")

echo "TOKEN=${TOKEN}"
```

### Step 2 — Create a user record

```bash
curl -s -X POST "${API}/users" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","name":"Test User"}' | python3 -m json.tool
```

### Step 3 — Create a product (browse service)

```bash
curl -s -X POST "${API}/products" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Wireless Headphones",
    "description": "Noise-cancelling Bluetooth headphones",
    "price": 99.99,
    "category": "electronics",
    "stock": 100
  }' | python3 -m json.tool

# List products
curl -s "${API}/products" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -m json.tool

# Get by ID (second call hits Redis cache)
PRODUCT_ID="<id from above>"
curl -s "${API}/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -m json.tool
```

### Step 4 — Search products

```bash
curl -s "${API}/search?q=headphones" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -m json.tool

# Filter by category and price range
curl -s "${API}/search?q=headphones&category=electronics&max_price=150" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -m json.tool
```

### Step 5 — Place an order (triggers async event flow)

```bash
USER_ID="<user_id from step 2>"
PRODUCT_ID="<product_id from step 3>"

ORDER=$(curl -s -X POST "${API}/orders" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"${USER_ID}\",
    \"items\": [{\"product_id\": \"${PRODUCT_ID}\", \"quantity\": 2}],
    \"payment_method\": \"credit_card\"
  }" | python3 -m json.tool)

echo "${ORDER}"
ORDER_ID=$(echo "${ORDER}" | python3 -c "import json,sys; print(json.load(sys.stdin)['order_id'])")
```

### Step 6 — Check order and shipment status

```bash
# Get order
curl -s "${API}/orders/${ORDER_ID}" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -m json.tool

# Get shipment (created asynchronously by shipping-service via SQS)
# Wait ~5s for the SQS consumer to process
sleep 5
curl -s "${API}/shipping/${ORDER_ID}" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -m json.tool
```

### Step 7 — Update shipment status

```bash
curl -s -X PATCH "${API}/shipping/${ORDER_ID}/status?status=delivered" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -m json.tool
```

### End-to-End verification checklist

| Step | What to verify |
|---|---|
| Login | `access_token` returned in response |
| Create user | `201` with `user_id` UUID |
| Create product | `201` with `product_id` UUID |
| List products | `200` array, product visible |
| Second GET product | Same response (Redis cache hit visible in browse-service logs) |
| Search | `200` with `hits` array, product found |
| Create order | `201` with `order_id` and `status: pending` |
| Get shipment after 5s | `200` with `tracking_number` and `status: processing` |
| Update shipment | `200` with new `status: delivered` |

### Run unit tests

```bash
cd /workshop
pytest tests/unit/ -v
```

---

## CI/CD Pipeline

The GitHub Actions pipeline (`.github/workflows/deploy.yml`) implements a
**build-once, promote-everywhere** pattern using the Git SHA as the image tag.

```
push to main
    │
    ▼
infra job        terraform apply (dev)
    │
    ▼
app job          unit tests → build 6 images → push ECR (tag: SHA[:8])
    │            update all ECS services → wait stable
    ▼
[manual gate]    terraform apply (preprod) → deploy same image tag
    │
    ▼
[manual gate]    terraform apply (prod) → deploy same image tag
```

Required GitHub secrets:

| Secret | Value |
|---|---|
| `AWS_ROLE_ARN` | IAM role ARN with ECS/ECR/Terraform permissions |
| `TF_STATE_BUCKET` | S3 bucket name for Terraform state |

The pipeline uses OIDC (`id-token: write`) — no long-lived AWS credentials stored in GitHub.

---

## Per-Environment Configuration

| Setting | dev | preprod | prod |
|---|---|---|---|
| VPC | Shared (`anycompany-nonprod-shared-vpc`) | Dedicated | Dedicated |
| NAT Gateway | None (VPC Endpoints) | Regional (1) | Zonal (2) |
| ECS task CPU | 256 | 512 | 1024 |
| ECS task memory | 512 MB | 1024 MB | 2048 MB |
| ECS desired count | 1 | 1 | 1 |
| ECS max count | 5 | 5 | 5 |
| Auto-scaling target | 60% CPU | 60% CPU | 60% CPU |
| OpenSearch | t3.small (1 node) | t3.small (1 node) | t3.small (1 node) |
| Redis | cache.t3.micro | cache.t3.micro | cache.t3.micro |
| DynamoDB | On-demand | On-demand | On-demand |

---

## Troubleshooting

### ECS task fails to start — `ResourceInitializationError`

Tasks in private subnets can't reach Secrets Manager or ECR.

```bash
# Check service events
aws ecs describe-services \
  --cluster anycompany-users-dev-cluster \
  --services anycompany-users-dev-login \
  --region us-east-1 \
  --query 'services[0].events[:5]'

# Verify VPC endpoints exist
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --query 'VpcEndpoints[*].{Service:ServiceName,State:State}' \
  --output table
```

Fix: run `terraform apply` — `vpc-endpoints.tf` creates the required endpoints.

### Task starts but crashes immediately

```bash
# Check CloudWatch logs
aws logs tail /ecs/anycompany-users-dev-login-service \
  --follow --region us-east-1
```

### Service stuck at 0 running / desired 1

```bash
# Check stopped tasks for error detail
aws ecs list-tasks \
  --cluster anycompany-users-dev-cluster \
  --desired-status STOPPED \
  --region us-east-1 \
  --query 'taskArns' --output text \
| xargs aws ecs describe-tasks \
  --cluster anycompany-users-dev-cluster \
  --region us-east-1 \
  --query 'tasks[*].{task:taskArn,reason:stoppedReason,containers:containers[*].{name:name,reason:reason}}' \
  --tasks
```

### Search returns no results after creating products

OpenSearch indexing is not automatic. Products must be indexed via the search-service
index endpoint, or the browse-service can be extended to publish to OpenSearch on write.
For now, verify the OpenSearch domain is reachable from the search-service task.

### Redis cache not working

```bash
# Check ElastiCache reachability (from a task in the same SG)
# The browse-service logs will show "cache miss" / "cache hit" on each GET /products/{id}
aws logs tail /ecs/anycompany-users-dev-browse-service \
  --follow --region us-east-1
```

### Shipment not created after order

The shipping-service polls SQS (`anycompany-users-dev-shipping-dispatch`) on a
background daemon thread. Check:

```bash
# SQS queue depth
aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/680136429538/anycompany-users-dev-shipping-dispatch \
  --attribute-names ApproximateNumberOfMessages \
  --region us-east-1

# Shipping service logs
aws logs tail /ecs/anycompany-users-dev-shipping-service \
  --follow --region us-east-1
```

### Force new deployment

```bash
aws ecs update-service \
  --cluster anycompany-users-dev-cluster \
  --service anycompany-users-dev-<name> \
  --force-new-deployment \
  --region us-east-1
```
