# Users Service — Implementation Tasks

Tasks ordered by dependency. Complete in sequence.

---

## Task 1 — Repository & Directory Scaffolding ✅

Establish source layout for both services, authorizer, K8s manifests, and tests.

**Create:**
```
src/
├── login/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── app/
│       ├── main.py           # FastAPI stub with /health
│       ├── config.py
│       ├── routers/auth.py   # stubs: /auth/login, /auth/refresh, /auth/logout
│       ├── models/auth.py
│       └── exceptions.py
└── users/
    ├── Dockerfile
    ├── requirements.txt
    └── app/
        ├── main.py
        ├── config.py
        ├── routers/users.py
        ├── models/user.py
        ├── services/user_service.py
        └── exceptions.py
src/authorizer/
├── lambda_authorizer.py
└── requirements.txt
k8s/
├── login-deployment.yaml
├── login-service.yaml
├── users-deployment.yaml
└── users-service.yaml
tests/unit/__init__.py
infrastructure/
├── shared/
└── env/
    └── environments/
        ├── dev.tfvars
        ├── mr.tfvars
        ├── preprod.tfvars
        └── prod.tfvars
```

**Verify:**
```bash
docker build -t login-service:local src/login/
docker build -t users-service:local src/users/
# Both build without errors; /health returns {"status":"ok"}
```

---

## Task 2 — Terraform Base ✅

Split into two root modules.

**`infrastructure/shared/`** — run once per account:
- `main.tf`: `terraform {}` block, S3 backend with key `shared/terraform.tfstate`
- `variables.tf`: `aws_region`, `project`
- `outputs.tf`: `vpc_id`, `private_subnet_ids`, `public_subnet_ids`

**`infrastructure/env/`** — run per environment:
- `provider.tf`: AWS provider pin; backend key `{env}/terraform.tfstate`
- `variables.tf`: `env`, `prefix = "anycompany-users-${var.env}"`, `aws_region`, `nat_gateway_mode = "regional"`
- `outputs.tf`: skeleton (filled by later tasks)
- `data.tf`: VPC lookup (see Task 3b)

**Verify:**
```bash
cd infrastructure/shared && terraform init && terraform validate
cd infrastructure/env   && terraform init -backend-config=environments/dev.tfvars && terraform validate
```

---

## Task 3 — Shared VPC with Regional NAT Gateway ✅

**Create:** `infrastructure/shared/vpc.tf`

Checklist:
- `aws_vpc` tagged `Name = "anycompany-nonprod-shared-vpc"`
- 2 public subnets (AZ a, b) + 2 private subnets (AZ a, b)
- `aws_internet_gateway`
- **One** `aws_nat_gateway` in public subnet az-a (regional mode)
- Both private route tables point to the single NAT GW
- `nat_gateway_mode` variable: `"zonal"` creates one per AZ via `for_each` (reserved for prod upgrade)

**Verify:**
```bash
cd infrastructure/shared && terraform apply -auto-approve
aws ec2 describe-nat-gateways \
  --filter "Name=tag:Name,Values=anycompany-nonprod-*" \
  | jq '[.NatGateways[]] | length'
# → 1
```

---

## Task 3b — VPC Data Source for env module ✅

**Create:** `infrastructure/env/data.tf`

```hcl
data "aws_vpc" "shared" {
  count = var.env == "dev" || startswith(var.env, "mr") ? 1 : 0
  tags  = { Name = "anycompany-nonprod-shared-vpc" }
}

resource "aws_vpc" "dedicated" {
  count      = var.env == "preprod" || var.env == "prod" ? 1 : 0
  cidr_block = var.vpc_cidr
}

locals {
  vpc_id = (var.env == "dev" || startswith(var.env, "mr")
    ? data.aws_vpc.shared[0].id
    : aws_vpc.dedicated[0].id)
}
```

All subsequent env module resources reference `local.vpc_id` and corresponding subnet data sources.
Preprod/prod also create their own NAT GW and route tables in `infrastructure/env/vpc.tf`.

---

## Task 4 — DynamoDB Table ✅

**Create:** `infrastructure/env/dynamodb.tf`

- `aws_dynamodb_table` named `${var.prefix}-users`, `billing_mode = "PAY_PER_REQUEST"`
- Hash key `user_id` (S)
- GSI `email-index`, PK `email` (S), projection ALL
- Tags: `env`, `project`

**Outputs:** `dynamodb_table_name`, `dynamodb_table_arn`

---

## Task 5 — Cognito User Pool ✅

**Create:** `infrastructure/env/cognito.tf`

- `aws_cognito_user_pool` `${var.prefix}-pool`, `username_attributes = ["email"]`
- `aws_cognito_user_pool_client`, `ALLOW_USER_PASSWORD_AUTH`, no client secret

**Outputs:** `cognito_user_pool_id`, `cognito_app_client_id`, `cognito_jwks_url`

---

## Task 6 — ECR Repositories ✅

**Create:** `infrastructure/env/ecr.tf`

- `aws_ecr_repository` for `anycompany-login-service` (created once in non-prod account; shared across MR + dev)
- `aws_ecr_repository` for `anycompany-users-service`
- Lifecycle policy: retain last 10 tagged images per repo
- Use `count` or `var.create_ecr` flag to skip creation in preprod/prod accounts (they pull from non-prod ECR)

**Outputs:** `login_ecr_url`, `users_ecr_url`

---

## Task 7 — Lambda Token Authorizer (Python) ✅

**Create/complete:** `src/authorizer/lambda_authorizer.py`

Logic:
1. Strip `Bearer ` from `event["authorizationToken"]`
2. Decode JWT header (no verify) → extract `kid`
3. Fetch JWKS from `COGNITO_JWKS_URL` env var; cache in module-level dict keyed by `kid`
4. Verify RS256 signature, `exp`, `iss` via `python-jose`
5. Success → `generate_policy("user", "Allow", event["methodArn"])`
6. Any failure → `raise Exception("Unauthorized")`

**Verify:** `pytest tests/unit/test_authorizer.py -v`

---

## Task 8 — Lambda Authorizer Terraform ✅

**Create:** `infrastructure/env/lambda-authorizer.tf`

- ZIP `src/authorizer/` via `archive_file`
- `aws_iam_role` + `AWSLambdaBasicExecutionRole`
- `aws_lambda_function` runtime `python3.10`, env `COGNITO_JWKS_URL`
- `aws_api_gateway_authorizer` type TOKEN, TTL 300 s, source `method.request.header.Authorization`

---

## Task 9 — EKS Cluster & IRSA Roles ✅

**Create:** `infrastructure/env/eks.tf`, `infrastructure/env/iam.tf`

- `aws_eks_cluster` + `aws_eks_node_group` (t3.medium, desired 2) in private subnets
- OIDC provider for IRSA
- **login-service IRSA role**: `cognito-idp:InitiateAuth`, `cognito-idp:GlobalSignOut` — no DynamoDB
- **users-service IRSA role**: DynamoDB `GetItem`, `PutItem`, `UpdateItem`, `DeleteItem`, `Query`, `Scan` on the users table ARN only

**Verify:**
```bash
aws eks update-kubeconfig --name ${var.prefix}-cluster --region us-east-1
kubectl get nodes   # → 2 Ready
```

---

## Task 10 — Kubernetes Namespace & Workload Infrastructure ✅

**Create:** `infrastructure/env/k8s-infra.tf`

Terraform manages only the K8s scaffolding — **not** the Deployment or Service:

- `kubernetes_namespace`: `anycompany-users-{env}`
- `kubernetes_service_account`: `login-service` with IRSA role ARN annotation
- `kubernetes_service_account`: `users-service` with IRSA role ARN annotation
- `kubernetes_network_policy`: default-deny ingress from other namespaces
- `kubernetes_config_map`: env-specific config (`TABLE_NAME`, `COGNITO_CLIENT_ID`, `COGNITO_USER_POOL_ID`, `AWS_REGION`)

**K8s workload manifests** live in `k8s/` and are applied by CI (not Terraform):

```yaml
# k8s/users-deployment.yaml (representative)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: users-service
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  template:
    spec:
      serviceAccountName: users-service
      containers:
        - name: users-service
          image: IMAGE_TAG          # substituted by CI: {ecr_url}:{env}-{sha}
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: anycompany-users-{env}-config
```

---

## Task 11 — Login Service Application (FastAPI) ✅

**Complete:** `src/login/app/`

Endpoints:
- `POST /auth/login` — `InitiateAuth` (USER_PASSWORD_AUTH) → `access_token`, `id_token`, `refresh_token`, `expires_in`
- `POST /auth/refresh` — `InitiateAuth` (REFRESH_TOKEN_AUTH) → new `access_token`
- `POST /auth/logout` — `GlobalSignOut` → 204

Config: `COGNITO_CLIENT_ID`, `COGNITO_USER_POOL_ID`, `AWS_REGION` from env.
Pydantic models for `LoginRequest`, `RefreshRequest`, `LogoutRequest`, `TokenResponse`.
CORS middleware matching Users Service. Standard error shape on all failures.

---

## Task 12 — Users Service Application (FastAPI) ✅

**Complete:** `src/users/app/`

- `create_user`, `get_user`, `update_user`, `delete_user`, `list_users`
- Duplicate-email check via `email-index` GSI
- ISO 8601 timestamps via `datetime.utcnow()`; server-generated UUID
- Standard error shape; CORS middleware

---

## Task 13 — NLB, VPC Link, API Gateway ✅

**Create:** `infrastructure/env/nlb.tf`, `infrastructure/env/vpc-link.tf`, `infrastructure/env/api-gateway.tf`

- NLB in public subnets; two target groups (login-service port, users-service port)
- `aws_api_gateway_vpc_link` → NLB
- `openapi.json`: `/auth/*` routes to login-service (no authorizer); `/users/*` routes to users-service (Token Authorizer)
- Stage `v1`; deployment triggered on OpenAPI body hash change
- `aws_lambda_permission` for API Gateway → Authorizer Lambda

**Verify:**
```bash
API_URL=$(terraform output -raw api_gateway_invoke_url)

# /users requires auth
curl -s -o /dev/null -w "%{http_code}" -X GET "$API_URL/users"
# → 401

# /auth is open (no authorizer); bad credentials → 401 from app, not 403 from authorizer
curl -s -o /dev/null -w "%{http_code}" -X POST "$API_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"x@x.com","password":"wrong"}'
# → 401
```

---

## Task 14 — Unit Tests: Login Service ✅

**Create:** `tests/unit/test_login.py`, `tests/unit/test_refresh.py`, `tests/unit/test_logout.py`

Mock `boto3` Cognito client with `unittest.mock`.

| Test | Expected |
|------|----------|
| Valid credentials | 200, all four token fields present |
| Invalid credentials | 401 |
| Missing password | 422 |
| Valid refresh token | 200, new `access_token` |
| Expired refresh token | 401 |
| Valid logout | 204 |
| Invalid logout token | 401 |

**Verify:** `pytest tests/unit/test_login* tests/unit/test_refresh* tests/unit/test_logout* -v`

---

## Task 15 — Unit Tests: Users Service ✅

**Create:** `tests/unit/conftest.py`, `tests/unit/test_create_user.py`, `test_get_user.py`, `test_update_user.py`, `test_delete_user.py`, `test_list_users.py`

`conftest.py`: `moto`-backed DynamoDB table fixture + FastAPI `TestClient`.

| File | Happy path | Error cases |
|------|------------|-------------|
| test_create_user | 201 with UUID | 422 bad email; 409 duplicate |
| test_get_user | 200 all fields | 404 missing; 400 bad UUID |
| test_update_user | 200, `updated_at` changes | 400 no fields; 404; 409 duplicate email |
| test_delete_user | 204 | 404 missing |
| test_list_users | 200 items + count | 400 bad limit; pagination token works |

**Verify:** `pytest tests/unit/ -v --tb=short`

---

## Task 16 — Unit Tests: Lambda Authorizer ✅

**Create:** `tests/unit/test_authorizer.py`

| Test | Expected |
|------|----------|
| Valid RS256 token | policy Effect = Allow |
| Expired token | raises `Exception("Unauthorized")` |
| Wrong signing key | raises `Exception("Unauthorized")` |
| Missing Bearer prefix | raises `Exception("Unauthorized")` |
| Two calls, same token | JWKS fetched once (module-level cache) |

**Verify:** `pytest tests/unit/test_authorizer.py -v`

---

## Task 17 — Environment Variable Files ✅

**Complete:** `infrastructure/env/environments/`

```hcl
# dev.tfvars
env              = "dev"
aws_region       = "us-east-1"
nat_gateway_mode = "regional"
create_ecr       = true

# mr.tfvars  (CI sets env = "mr-${MR_NUMBER}" at runtime)
env              = "mr"
aws_region       = "us-east-1"
nat_gateway_mode = "regional"
create_ecr       = false   # reuse non-prod ECR repos created by dev

# preprod.tfvars
env              = "preprod"
aws_region       = "us-east-1"
nat_gateway_mode = "regional"
create_ecr       = false   # pull from non-prod ECR

# prod.tfvars
env              = "prod"
aws_region       = "us-east-1"
nat_gateway_mode = "regional"   # change to "zonal" if cross-AZ cost becomes significant
create_ecr       = false
```

---

## Task 18 — CI/CD Pipeline ✅

**Create:** `.github/workflows/deploy.yml` (or `.gitlab-ci.yml`)

### Infrastructure path (triggered on changes to `infrastructure/**`)

```
terraform init
terraform apply -var-file=environments/{env}.tfvars -auto-approve
```

Runs in the target account via OIDC `AssumeRoleWithWebIdentity`. No static credentials.

### Application path (triggered on changes to `src/**`)

```
1. pytest tests/unit/ -v                          # fail fast

2. docker build -t {ecr_url}:{env}-{sha} src/login/
   docker push {ecr_url}:{env}-{sha}
   docker build -t {ecr_url}:{env}-{sha} src/users/
   docker push {ecr_url}:{env}-{sha}

3. kubectl set image deployment/login-service \
     login-service={login_ecr_url}:{env}-{sha} \
     -n anycompany-users-{env}

   kubectl set image deployment/users-service \
     users-service={users_ecr_url}:{env}-{sha} \
     -n anycompany-users-{env}

4. kubectl rollout status deployment/login-service -n anycompany-users-{env} --timeout=5m
   kubectl rollout status deployment/users-service -n anycompany-users-{env} --timeout=5m
```

### MR lifecycle

| Event | Action |
|-------|--------|
| MR opened | Infrastructure path → `terraform apply` (shared VPC already exists; creates namespace + app resources) + Application path |
| Push to MR branch | Application path only (`docker build` + `kubectl set image`) |
| MR closed / merged | `terraform destroy -var env=mr-{N}` — tears down all env resources; shared VPC untouched |

### Account routing

| env | AWS account | Gate |
|-----|-------------|------|
| mr-N, dev | Non-prod | Automatic |
| preprod | Preprod | Automatic after dev passes |
| prod | Prod | Manual approval |

---

## Task 19 — Integration Smoke Test ✅

**Create:** `tests/integration/smoke_test.py`

Sequence (uses the deployed API):
1. `POST /auth/login` → get `access_token`
2. `POST /users` (with token) → 201; save `user_id`
3. `GET /users/{user_id}` → 200; fields match
4. `PUT /users/{user_id}` → 200; `updated_at` > `created_at`
5. `GET /users` → 200; user in `items`
6. `DELETE /users/{user_id}` → 204
7. `GET /users/{user_id}` → 404
8. `POST /users` without token → 401
9. `POST /auth/refresh` → 200; new `access_token`
10. `POST /auth/logout` → 204

**Run:**
```bash
API_URL=$(terraform -chdir=infrastructure/env output -raw api_gateway_invoke_url) \
  COGNITO_CLIENT_ID=$(terraform -chdir=infrastructure/env output -raw cognito_app_client_id) \
  TEST_EMAIL=smoke@anycompany.com \
  TEST_PASSWORD=TestPass123! \
  python tests/integration/smoke_test.py
```

---

## Dependency Order

```
Task 1  (Scaffold)
└─► Task 2  (Terraform base)
      ├─► Task 3  (Shared VPC)
      │     └─► Task 3b (VPC data source)
      ├─► Task 4  (DynamoDB)
      ├─► Task 5  (Cognito)
      │     ├─► Task 7  (Authorizer Python) ──► Task 16 (Unit tests: authorizer)
      │     │     └─► Task 8  (Authorizer Terraform)
      │     ├─► Task 11 (Login Service app) ──► Task 14 (Unit tests: login)
      │     └─► Task 12 (Users Service app) ──► Task 15 (Unit tests: users)
      ├─► Task 6  (ECR)
      ├─► Task 9  (EKS + IRSA)
      │     └─► Task 10 (K8s namespace + infra)
      │           └─► Task 13 (NLB + VPC Link + API Gateway)
      │                 └─► Task 19 (Smoke test)
      └─► Task 17 (Env var files)
            └─► Task 18 (CI/CD pipeline)
```
