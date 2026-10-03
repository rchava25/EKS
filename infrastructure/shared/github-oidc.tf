# GitHub Actions OIDC — allows GitHub Actions to assume AWS IAM roles
# without storing static credentials in GitHub secrets.
#
# Apply once per AWS account. The same provider serves all environments
# in that account (dev + all mr-* in non-prod; preprod in preprod account).

variable "github_org" {
  description = "GitHub organisation or username that owns the repo"
  type        = string
  default     = "rchava25"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "EKS"
}

# ── OIDC Provider ─────────────────────────────────────────────────────────────

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC thumbprint — stable; rotate only if GitHub rotates their CA.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name    = "github-actions-oidc"
    Project = var.project
  }
}

# ── Trust policy helper ────────────────────────────────────────────────────────

locals {
  github_oidc_arn = aws_iam_openid_connect_provider.github.arn
  oidc_subject_prefix = "repo:${var.github_org}/${var.github_repo}:"
}

data "aws_iam_policy_document" "github_oidc_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Allow any branch / PR / environment in this repo
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.oidc_subject_prefix}*"]
    }
  }
}

# ── Non-prod deploy role (dev + mr-*) ─────────────────────────────────────────

resource "aws_iam_role" "github_nonprod_deploy" {
  name               = "${var.project}-github-nonprod-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_trust.json

  tags = {
    Name    = "${var.project}-github-nonprod-deploy"
    Project = var.project
  }
}

# Broad permissions needed: EKS, ECR, DynamoDB, Cognito, Lambda, API GW,
# IAM (for IRSA role creation), EC2 (VPC/NLB), CloudWatch Logs.
resource "aws_iam_role_policy" "github_nonprod_deploy" {
  name = "deploy-permissions"
  role = aws_iam_role.github_nonprod_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKS"
        Effect = "Allow"
        Action = [
          "eks:*",
        ]
        Resource = "*"
      },
      {
        Sid    = "ECR"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeRepositories",
          "ecr:CreateRepository",
          "ecr:ListImages",
          "ecr:PutLifecyclePolicy",
        ]
        Resource = "*"
      },
      {
        Sid    = "DynamoDB"
        Effect = "Allow"
        Action = ["dynamodb:*"]
        Resource = "*"
      },
      {
        Sid    = "Cognito"
        Effect = "Allow"
        Action = ["cognito-idp:*"]
        Resource = "*"
      },
      {
        Sid    = "Lambda"
        Effect = "Allow"
        Action = ["lambda:*"]
        Resource = "*"
      },
      {
        Sid    = "APIGateway"
        Effect = "Allow"
        Action = ["apigateway:*"]
        Resource = "*"
      },
      {
        Sid    = "IAM"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:PassRole",
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2andVPC"
        Effect = "Allow"
        Action = [
          "ec2:*",
          "elasticloadbalancing:*",
        ]
        Resource = "*"
      },
      {
        Sid    = "S3StateBackend"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = "*"
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = ["logs:*"]
        Resource = "*"
      },
      {
        Sid    = "SSM"
        Effect = "Allow"
        Action = ["ssm:GetParameter"]
        Resource = "*"
      }
    ]
  })
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "github_nonprod_deploy_role_arn" {
  description = "IAM role ARN for GitHub Actions — set as NONPROD_DEPLOY_ROLE_ARN secret in GitHub"
  value       = aws_iam_role.github_nonprod_deploy.arn
}
