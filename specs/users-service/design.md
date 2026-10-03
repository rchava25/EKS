# Users Service — Architecture Design

## 1. Account & Environment Topology

```
┌──────────────────────────────────────────────┐
│  Non-Prod Account                            │
│  ┌────────────────────────────────────────┐  │
│  │  Shared VPC (one regional NAT GW)      │  │
│  │  ┌──────────────┐  ┌────────────────┐  │  │
│  │  │  dev         │  │  mr-N          │  │  │
│  │  │  (namespace) │  │  (namespace)   │  │  │
│  │  └──────────────┘  └────────────────┘  │  │
│  └────────────────────────────────────────┘  │
│  Per-env: DynamoDB, Cognito, API Gateway     │
└──────────────────────────────────────────────┘

┌──────────────────────────────────────┐
│  Preprod Account                     │
│  ┌──────────────────────────────┐    │
│  │  Dedicated VPC (regional NGW)│    │
│  └──────────────────────────────┘    │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│  Prod Account                        │
│  ┌──────────────────────────────┐    │
│  │  Dedicated VPC (regional NGW)│    │
│  └──────────────────────────────┘    │
└──────────────────────────────────────┘
```

Promotion flow: `mr-N` → `dev` → `preprod` → (manual gate) → `prod`

---

## 2. VPC Design

### Non-Prod Shared VPC (dev + all MR environments)

```
VPC: 10.0.0.0/16

Public subnets  (AZ a, b):  10.0.0.0/24   10.0.1.0/24
Private subnets (AZ a, b):  10.0.10.0/24  10.0.11.0/24

Internet Gateway → public subnets
One regional NAT Gateway in public subnet az-a
Both private route tables → single NAT GW
```

Created **once** via the `infrastructure/shared/` Terraform root module.
`dev` and `mr-N` environments look up the VPC by tag via a `data "aws_vpc"` data source.

### Preprod / Prod (dedicated VPCs)

Each has its own VPC, subnets, and regional NAT Gateway, created inline by the per-env module.
Setting `nat_gateway_mode = "zonal"` in `prod.tfvars` upgrades to one NAT GW per AZ if
cross-AZ cost becomes significant.

### Isolation within the shared VPC

| Layer   | Mechanism |
|---------|-----------|
| Compute | Separate Kubernetes namespace per env (`dev`, `mr-{N}`) |
| Network | K8s NetworkPolicy: pods in namespace X cannot reach pods in namespace Y |
| Data    | Separate DynamoDB table per env (`anycompany-users-{env}-users`) |
| Auth    | Separate Cognito User Pool per env |
| API     | Separate API Gateway REST API + stage per env |

---

## 3. System Diagram (per environment)

```
  Client
    │ HTTPS
    ▼
┌───────────────────────────────────┐
│  API Gateway REST (v1)            │ ◄── OpenAPI 3.0 body
│  /auth/*  → Login Service (open)  │
│  /users/* → Users Service (authed)│
└──────────┬────────────────────────┘
           │ VPC Link           Lambda Token Authorizer
           │                    (on /users/* only)
           ▼                          │ JWKS fetch
  ┌────────────────┐         ┌────────▼──────────┐
  │  NLB (public)  │         │  Amazon Cognito   │
  └──────┬─────────┘         │  User Pool        │
         │                   └───────────────────┘
         ▼
  ┌──────────────────────────────────────────┐
  │  EKS Cluster (private subnets)           │
  │  Namespace: anycompany-users-{env}       │
  │  ┌───────────────────┐  ┌─────────────┐ │
  │  │  Login Service    │  │Users Service│ │
  │  │  Python/FastAPI   │  │Python/FastAPI│ │
  │  │  Port 8080        │  │Port 8080    │ │
  │  └─────────┬─────────┘  └──────┬──────┘ │
  └────────────│──────────────────│─────────┘
               │ Cognito SDK       │ boto3 (IRSA)
               ▼                   ▼
  ┌──────────────────┐   ┌──────────────────────┐
  │  Amazon Cognito  │   │  Amazon DynamoDB      │
  │  User Pool       │   │  {prefix}-users table │
  └──────────────────┘   └──────────────────────┘
```

---

## 4. Services

### 4.1 Login Service (`anycompany-login-service`)

Handles all authentication interactions with Cognito. No DynamoDB access.

| Method | Path         | Description |
|--------|--------------|-------------|
| POST   | /auth/login  | `InitiateAuth` (USER_PASSWORD_AUTH) → tokens |
| POST   | /auth/refresh| `InitiateAuth` (REFRESH_TOKEN_AUTH) → new access token |
| POST   | /auth/logout | `GlobalSignOut` → revoke tokens |

IRSA role: Cognito `InitiateAuth`, `GlobalSignOut` only.

### 4.2 Users Service (`anycompany-users-service`)

Handles CRUD on user records. Protected by Lambda Token Authorizer on all routes.

| Method | Path               | Auth |
|--------|--------------------|------|
| POST   | /users             | ✓    |
| GET    | /users             | ✓    |
| GET    | /users/{user_id}   | ✓    |
| PUT    | /users/{user_id}   | ✓    |
| DELETE | /users/{user_id}   | ✓    |
| OPTIONS| /users, /users/{id}| —    |

IRSA role: DynamoDB `GetItem`, `PutItem`, `UpdateItem`, `DeleteItem`, `Query`, `Scan` on the users table ARN only.

---

## 5. Docker Images & Deployment

| Image | Source dir | ECR repo |
|-------|-----------|----------|
| `anycompany-login-service` | `src/login/` | `{account}.dkr.ecr.{region}.amazonaws.com/anycompany-login-service` |
| `anycompany-users-service` | `src/users/` | `{account}.dkr.ecr.{region}.amazonaws.com/anycompany-users-service` |

Tag format: `{env}-{git-sha}` (e.g. `dev-a1b2c3d`)

### Deploy process

Infrastructure changes (`infrastructure/**`) go through `terraform apply`.  
Application image updates (`src/**`) bypass Terraform entirely:

```
1. docker build + push to ECR  → tag: {env}-{git-sha}

2. kubectl set image deployment/login-service \
     login-service={ecr_url}:{env}-{sha} -n anycompany-users-{env}

3. kubectl set image deployment/users-service \
     users-service={ecr_url}:{env}-{sha} -n anycompany-users-{env}

4. kubectl rollout status deployment/login-service -n anycompany-users-{env}
   kubectl rollout status deployment/users-service -n anycompany-users-{env}
```

---

## 6. DynamoDB Schema

### Table: `anycompany-users-{env}-users`

| Attribute    | Type | Role                 | Notes |
|--------------|------|----------------------|-------|
| `user_id`    | S    | Partition Key        | UUID v4, server-generated |
| `email`      | S    | GSI PK (email-index) | Unique across all items |
| `name`       | S    | Attribute            | 1–128 chars |
| `status`     | S    | Attribute            | `ACTIVE` \| `INACTIVE` |
| `created_at` | S    | Attribute            | ISO 8601 UTC |
| `updated_at` | S    | Attribute            | ISO 8601 UTC, refreshed on every write |

GSI `email-index`: PK `email`, projection ALL — O(1) duplicate-email detection.

---

## 7. Terraform Layout

```
infrastructure/
├── shared/                  ← run once per account (creates shared VPC)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── vpc.tf
└── env/                     ← run per environment
    ├── provider.tf
    ├── variables.tf
    ├── outputs.tf
    ├── data.tf              ← looks up shared VPC (non-prod) or creates dedicated VPC
    ├── vpc.tf               ← dedicated VPC for preprod/prod only
    ├── dynamodb.tf
    ├── cognito.tf
    ├── ecr.tf               ← one repo per image (non-prod account only; shared across envs)
    ├── eks.tf               ← EKS cluster; namespace + IRSA per env
    ├── iam.tf               ← IRSA roles for login-service and users-service
    ├── k8s-infra.tf         ← namespace, service accounts, network policies, config maps
    ├── nlb.tf
    ├── vpc-link.tf
    ├── lambda-authorizer.tf
    ├── cognito.tf
    └── api-gateway.tf
```

```
infrastructure/environments/
├── dev.tfvars
├── mr.tfvars       ← CI substitutes MR_NUMBER into var.env
├── preprod.tfvars
└── prod.tfvars
```

```
k8s/
├── login-deployment.yaml    ← image tag substituted by CI at deploy time
├── login-service.yaml
├── users-deployment.yaml
└── users-service.yaml
```

Backend: `shared/terraform.tfstate` for shared module; `{env}/terraform.tfstate` for each env.  
All resource names prefixed `anycompany-users-{env}-`.

---

## 8. Multi-Account CI/CD

```
CI Pipeline
    │
    ├─ OIDC → AssumeRole → Non-Prod Account  (mr-N, dev)
    ├─ OIDC → AssumeRole → Preprod Account   (preprod)
    └─ OIDC → AssumeRole → Prod Account      (prod, manual gate)
```

Each account has an IAM role with a trust policy scoped to the CI OIDC provider.
No long-lived AWS credentials stored in CI.

---

## 9. Security Controls

| Area | Control |
|------|---------|
| Token validation | Lambda Authorizer; RS256 vs Cognito JWKS; verifies `exp`, `iss`, `aud` |
| DynamoDB access  | IRSA least-privilege; users-service role only; specific table ARN |
| Login service    | IRSA role has no DynamoDB permissions |
| Cross-account    | OIDC-scoped IAM roles; no static credentials |
| Cross-namespace  | K8s NetworkPolicy blocks inter-namespace pod traffic |
| Stack traces     | Exception handlers return generic 500; details to CloudWatch only |
| Input validation | Pydantic v2 validates all request bodies |
