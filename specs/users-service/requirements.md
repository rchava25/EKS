# Users Service — Requirements

## Overview

RESTful API platform for AnyCompany user management across four environments
(mr, dev, preprod, prod). Protected by JWT-based authentication served by a dedicated
Login Service. Backed by DynamoDB. Infrastructure deployed to AWS via Terraform.

---

## 1. User CRUD (Users Service)

### US-01 Create a User
**As an** authenticated API client  
**I want to** POST a JSON payload to create a user record  
**So that** a unique user account is persisted and retrievable by its generated ID

**Acceptance Criteria**
- AC-01.1: `POST /users` with valid `email` (RFC 5321) and `name` (1–128 chars) returns **201** with the full user object.
- AC-01.2: Response body contains `user_id` (UUID v4), `email`, `name`, `status` (`ACTIVE`), `created_at` (ISO 8601 UTC), `updated_at` (ISO 8601 UTC, equal to `created_at` on creation).
- AC-01.3: `user_id` is generated server-side; any caller-supplied value is ignored.
- AC-01.4: Duplicate `email` returns **409** with an `error` field.
- AC-01.5: Missing or invalid `email` returns **422** with an `error` field.
- AC-01.6: Missing or out-of-range `name` returns **422** with an `error` field.

### US-02 Retrieve a User
- AC-02.1: `GET /users/{user_id}` returns **200** with the full user object.
- AC-02.2: Unknown `user_id` returns **404**.
- AC-02.3: Malformed `user_id` (not a valid UUID) returns **400**.

### US-03 Update a User
- AC-03.1: `PUT /users/{user_id}` with one or more of `email`, `name` returns **200** with the updated object.
- AC-03.2: Fields not in the payload are unchanged.
- AC-03.3: `updated_at` refreshed on every successful update; `created_at` never changes.
- AC-03.4: Updating `email` to one owned by another user returns **409**.
- AC-03.5: Unknown user returns **404**.
- AC-03.6: Body with no recognised mutable field returns **400**.

### US-04 Delete a User
- AC-04.1: `DELETE /users/{user_id}` returns **204** with no body.
- AC-04.2: After deletion, `GET /users/{user_id}` returns **404**.
- AC-04.3: Deleting a non-existent user returns **404**.

### US-05 List Users
- AC-05.1: `GET /users` returns **200** with `{ items: [...], count: N }`.
- AC-05.2: `limit` query param (1–100, default 20) controls page size.
- AC-05.3: More results → response includes `next_token` for cursor-based pagination.
- AC-05.4: Passing `next_token` returns the next page.
- AC-05.5: Invalid `limit` returns **400**.

---

## 2. Authentication (Login Service)

### US-06 User Login
**As an** API consumer  
**I want to** exchange credentials for a JWT access token  
**So that** I can call protected endpoints

- AC-06.1: `POST /auth/login` with valid `email` and `password` returns **200** with `access_token`, `id_token`, `refresh_token`, and `expires_in`.
- AC-06.2: Invalid credentials return **401** with `{"error": "Invalid credentials", "status_code": 401}`.
- AC-06.3: Missing fields return **422**.

### US-07 Token Refresh
- AC-07.1: `POST /auth/refresh` with a valid `refresh_token` returns **200** with a new `access_token` and `expires_in`.
- AC-07.2: Expired or invalid `refresh_token` returns **401**.

### US-08 Logout
- AC-08.1: `POST /auth/logout` with a valid `access_token` revokes the token in Cognito and returns **204**.
- AC-08.2: Invalid token returns **401**.

### US-09 Token Authorizer (API Gateway)
- AC-09.1: Valid `Bearer <token>` in `Authorization` on any Users Service endpoint allows the request.
- AC-09.2: Missing, malformed, expired, or wrongly-signed tokens return **401**.
- AC-09.3: Authorizer cache TTL ≥ 300 s; repeated calls within the window do not re-invoke Lambda.
- AC-09.4: Token validation is performed by the Lambda Authorizer; services do not re-validate.

---

## 3. CORS

### US-10 CORS Support
- AC-10.1: `OPTIONS` requests return **200** with `Access-Control-Allow-Origin: *`, correct `Allow-Methods` and `Allow-Headers`.
- AC-10.2: CORS headers present on **all** responses, including errors.
- AC-10.3: `OPTIONS` routes bypass the Lambda Token Authorizer.

---

## 4. Error Shape

### US-11 Consistent Errors
- AC-11.1: Every non-2xx response body is JSON with an `error` (string) key.
- AC-11.2: 4xx/5xx bodies include `status_code` integer matching the HTTP status.
- AC-11.3: Internal stack traces never exposed in responses.
- AC-11.4: Unhandled exceptions return **500** without crashing the process.

---

## 5. Multi-Environment Deployment

### US-12 Environment Isolation
- AC-12.1: Each environment (mr, dev, preprod, prod) has isolated application resources: separate DynamoDB table, Cognito pool, EKS namespace, and API Gateway stage.
- AC-12.2: `mr` and `dev` environments share a single VPC in the **non-prod account**; `preprod` has its own VPC in the **preprod account**; `prod` has its own VPC in the **prod account**.
- AC-12.3: All resource names are prefixed with `anycompany-users-{env}-` to avoid collisions.
- AC-12.4: Kubernetes NetworkPolicies prevent cross-namespace pod traffic within the shared non-prod VPC.

### US-13 Ephemeral MR Environments
- AC-13.1: Opening a merge request automatically provisions a fresh `mr-{MR_NUMBER}` environment.
- AC-13.2: Closing or merging the MR automatically destroys the environment (`terraform destroy`).
- AC-13.3: MR environments are created in the non-prod account and share the non-prod VPC.

### US-14 Promotion Gates
- AC-14.1: Deployment to `preprod` requires passing CI tests on `dev`.
- AC-14.2: Deployment to `prod` requires manual approval after a successful `preprod` deployment.

---

## 6. Non-Functional Requirements

| ID    | Category      | Requirement |
|-------|---------------|-------------|
| NF-01 | Observability | Every request logged at INFO with `method`, `path`, `status_code`, `duration_ms`. |
| NF-02 | Observability | Logger via `logging.getLogger(__name__)` at module level. |
| NF-03 | Reliability   | DynamoDB PAY_PER_REQUEST billing per environment. |
| NF-04 | Networking    | Single regional NAT Gateway in the non-prod shared VPC; one per dedicated VPC (preprod, prod). |
| NF-05 | Portability   | Login Service and Users Service each packaged as a separate Docker image deployed to EKS. |
| NF-06 | IaC           | All infrastructure in Terraform; one `.tf` file per logical component. |
| NF-07 | Deploy        | Application image updates use `kubectl set image`; `terraform apply` is reserved for infrastructure changes. |
| NF-08 | Testability   | Unit tests under `tests/unit/` with `pytest` + `moto`; no live AWS calls. |
