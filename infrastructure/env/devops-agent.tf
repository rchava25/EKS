# ── AWS DevOps Agent ──────────────────────────────────────────────────────────
# Fully managed AI agent that monitors infrastructure, performs root cause
# analysis on operational events, and runs automated remediation — replacing
# the need for a dedicated on-call engineer.
#
# Uses the awscc provider (AWS Cloud Control API) >= 1.98.0.
# Supported regions: us-east-1, us-west-2, ap-southeast-2, ap-northeast-1,
#                    eu-central-1, eu-west-1.

# ── IAM: Agent Space role ─────────────────────────────────────────────────────
# Assumed by the DevOps Agent service to monitor and remediate this account.

resource "aws_iam_role" "devops_agent_space" {
  name = "${local.prefix}-devops-agent-space-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "aidevops.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })

  tags = {
    Name    = "${local.prefix}-devops-agent-space-role"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_iam_role_policy_attachment" "devops_agent_space" {
  role       = aws_iam_role.devops_agent_space.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsAgentAccessPolicy"
}

# Allows DevOps Agent to create the Resource Explorer service-linked role
# so it can discover and index resources in the account automatically.
resource "aws_iam_role_policy" "devops_agent_resource_explorer" {
  name = "resource-explorer-slr"
  role = aws_iam_role.devops_agent_space.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "iam:CreateServiceLinkedRole"
      Resource = "arn:aws:iam::*:role/aws-service-role/resource-explorer-2.amazonaws.com/*"
      Condition = {
        StringLike = {
          "iam:AWSServiceName" = "resource-explorer-2.amazonaws.com"
        }
      }
    }]
  })
}

# ── IAM: Operator App role ────────────────────────────────────────────────────
# Used by the DevOps Agent operator app to take remediation actions.

resource "aws_iam_role" "devops_agent_operator" {
  name = "${local.prefix}-devops-agent-operator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "aidevops.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })

  tags = {
    Name    = "${local.prefix}-devops-agent-operator-role"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_iam_role_policy_attachment" "devops_agent_operator" {
  role       = aws_iam_role.devops_agent_operator.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsOperatorAppAccessPolicy"
}

# ── Caller identity (needed for account ID in trust policies) ─────────────────

data "aws_caller_identity" "current" {}

# ── Sleep: IAM propagation delay ──────────────────────────────────────────────
# DevOps Agent validates the operator role trust policy at agent space creation.
# Without this pause the create call occasionally fails with a trust policy error.

resource "time_sleep" "iam_propagation" {
  depends_on      = [aws_iam_role_policy_attachment.devops_agent_operator]
  create_duration = "30s"
}

# ── Agent Space ───────────────────────────────────────────────────────────────

resource "awscc_devopsagent_agent_space" "main" {
  name        = "${local.prefix}-agent-space"
  description = "AI DevOps Agent for AnyCompany Users Service (${var.env})"

  operator_app = {
    iam = {
      operator_app_role_arn = aws_iam_role.devops_agent_operator.arn
    }
  }

  depends_on = [time_sleep.iam_propagation]
}

# ── AWS Account Association ────────────────────────────────────────────────────
# Links this AWS account to the agent space so DevOps Agent can monitor and
# remediate resources (EKS, ALB, DynamoDB, Lambda, API Gateway, Cognito).

resource "awscc_devopsagent_association" "this_account" {
  agent_space_id = awscc_devopsagent_agent_space.main.id
  service_id     = "aws"

  configuration = {
    aws = {
      assumable_role_arn = aws_iam_role.devops_agent_space.arn
      account_id         = data.aws_caller_identity.current.account_id
      account_type       = "monitor"
      resources          = []
    }
  }

  depends_on = [awscc_devopsagent_agent_space.main]
}

# ── Custom Skill: AnyCompany Users Service ────────────────────────────────────
# Teaches the agent the specific failure patterns, runbooks, and context
# for this service. Loaded automatically when relevant issues are detected.

resource "awscc_devopsagent_asset" "users_service_skill" {
  agent_space_id = awscc_devopsagent_agent_space.main.id
  asset_type     = "skill"

  metadata = jsonencode({
    name        = "anycompany-users-service-runbook"
    description = "Runbooks and known failure patterns for the AnyCompany Users Service on EKS."
    agent_types = ["GENERIC"]
  })

  files = [{
    path         = "SKILL.md"
    content_text = <<-EOT
      # AnyCompany Users Service — Runbook

      ## Architecture
      - API Gateway (REST) → VPC Link → Internal ALB → EKS pods
      - Services: login-service (port 8080), users-service (port 8080)
      - Namespace: anycompany-users-${var.env}
      - Database: DynamoDB table anycompany-users-${var.env}-users
      - Auth: Cognito User Pool + Lambda token authorizer
      - Load balancing: AWS LBC + TargetGroupBinding (IP mode)
      - Autoscaling: HPA min=2 max=5 CPU target=50%

      ## Known Failure Patterns

      ### Pod crash loop (OOMKilled)
      - Symptom: Pod status OOMKilled, restartCount increasing
      - Cause: Memory limit (512Mi) exceeded — likely large DynamoDB scan or memory leak
      - Action: kubectl rollout restart deployment/<name> -n anycompany-users-${var.env}
      - Prevention: Add pagination to list endpoints, investigate memory growth

      ### Pod crash loop (unknown error)
      - Symptom: CrashLoopBackOff, restartCount > 3
      - Action: kubectl logs -n anycompany-users-${var.env} -l app=users-service --previous
      - Then: kubectl rollout restart deployment/users-service -n anycompany-users-${var.env}

      ### ALB target group unhealthy
      - Symptom: All TG targets show unhealthy, 503 from API Gateway
      - Check: /health endpoint on port 8080 should return 200
      - Action: Verify pods are running and readinessProbe is passing
      - Command: kubectl get pods -n anycompany-users-${var.env}

      ### API Gateway 403 after login
      - Symptom: POST /auth/login succeeds but GET /users returns 403
      - Cause: Lambda authorizer cache (300s TTL) returning policy scoped to wrong method ARN
      - Action: Flush authorizer cache via API Gateway console or redeploy stage
      - Long-term: Authorizer already returns wildcard ARN — check if Lambda was redeployed

      ### API Gateway 500 on /users/{user_id}
      - Symptom: Path parameter routes return 500, collection routes work
      - Cause: Missing requestParameters mapping in API Gateway integration
      - Action: Redeploy API Gateway stage: aws apigateway create-deployment --rest-api-id <id> --stage-name ${var.env}

      ### DynamoDB throttling
      - Symptom: ProvisionedThroughputExceededException in pod logs
      - Table uses PAY_PER_REQUEST — throttling indicates burst beyond DynamoDB limits
      - Action: Check for runaway scan operations, add exponential backoff retry

      ### TargetGroupBinding not registering pods
      - Symptom: TG shows no targets despite pods running
      - Check: kubectl describe targetgroupbinding -n anycompany-users-${var.env}
      - Common cause: serviceRef.port must match Service port (80), not containerPort (8080)

      ### HPA not scaling
      - Symptom: CPU high but pod count stays at minimum
      - Check: kubectl describe hpa -n anycompany-users-${var.env}
      - Common cause: metrics-server not running or no resource requests set on pods
      - Action: kubectl get pods -n kube-system | grep metrics-server

      ### Cognito 401 Invalid credentials
      - Symptom: Login returns 401 despite correct password
      - Check: User may be in FORCE_CHANGE_PASSWORD state
      - Action: aws cognito-idp admin-set-user-password --user-pool-id <id> --username <email> --password <pass> --permanent
    EOT
  }]
}

# ── Custom Agent: AnyCompany Firefighter ──────────────────────────────────────
# Scoped agent that attaches the service runbook skill and focuses investigation
# on the users service stack.

resource "awscc_devopsagent_asset" "users_service_agent" {
  agent_space_id = awscc_devopsagent_agent_space.main.id
  asset_type     = "custom_agent"

  metadata = jsonencode({
    name   = "anycompany-users-firefighter"
    skills = [awscc_devopsagent_asset.users_service_skill.asset_id]
  })

  files = [{
    path         = "AGENT.md"
    content_text = <<-EOT
      # AnyCompany Users Firefighter

      You are an on-call engineer for the AnyCompany Users Service running on EKS in ${var.env}.

      When investigating an issue:
      1. Check pod status and recent logs in namespace anycompany-users-${var.env}
      2. Check ALB target group health for login-tg and users-tg
      3. Check DynamoDB table anycompany-users-${var.env}-users for throttling
      4. Check Lambda authorizer anycompany-users-${var.env}-token-authorizer for errors
      5. Check API Gateway anycompany-users-${var.env}-api for 4xx/5xx rates
      6. Consult the service runbook skill for known patterns before escalating
      7. Attempt safe automated remediation (pod restart, HPA scale) before escalating
      8. Escalate with a clear root cause summary if remediation fails or confidence is low
    EOT
  }]
}

# ── Scheduled Trigger: Daily health check ─────────────────────────────────────
# Runs the firefighter agent once per day to proactively surface issues
# before they become user-impacting incidents.

resource "awscc_devopsagent_trigger" "daily_health_check" {
  agent_space_id = awscc_devopsagent_agent_space.main.id
  type           = "TIME_BASED"

  condition = {
    schedule = {
      expression = "rate(1 day)"
    }
  }

  action = jsonencode({
    actionType = "create:task"
    task = {
      agent = "custom:${awscc_devopsagent_asset.users_service_agent.asset_id}"
    }
  })

  status = "Active"
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "devops_agent_space_id" {
  description = "DevOps Agent Space ID — use this to query incidents via CLI"
  value       = awscc_devopsagent_agent_space.main.agent_space_id
}

output "devops_agent_space_arn" {
  description = "DevOps Agent Space ARN"
  value       = awscc_devopsagent_agent_space.main.agent_space_arn
}
