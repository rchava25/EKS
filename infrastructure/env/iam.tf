locals {
  # Strip "https://" prefix for use as the OIDC condition variable key.
  oidc_host = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

# ── login-service IRSA Role ───────────────────────────────────────────────────
# Cognito only — no DynamoDB permissions.

resource "aws_iam_role" "login_service" {
  name = "${local.prefix}-login-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_host}:sub" = "system:serviceaccount:${local.prefix}:login-service"
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name    = "${local.prefix}-login-service-role"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_iam_role_policy" "login_service_cognito" {
  name = "${local.prefix}-login-cognito"
  role = aws_iam_role.login_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "cognito-idp:InitiateAuth",
        "cognito-idp:GlobalSignOut",
      ]
      Resource = aws_cognito_user_pool.main.arn
    }]
  })
}

# ── users-service IRSA Role ───────────────────────────────────────────────────
# DynamoDB only — no Cognito permissions.

resource "aws_iam_role" "users_service" {
  name = "${local.prefix}-users-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_host}:sub" = "system:serviceaccount:${local.prefix}:users-service"
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name    = "${local.prefix}-users-service-role"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_iam_role_policy" "users_service_dynamodb" {
  name = "${local.prefix}-users-dynamodb"
  role = aws_iam_role.users_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan",
      ]
      # Allow access to table and all its indexes (needed for GSI queries).
      Resource = [
        aws_dynamodb_table.users.arn,
        "${aws_dynamodb_table.users.arn}/index/*",
      ]
    }]
  })
}

output "login_service_role_arn" {
  description = "IRSA role ARN for the login-service pods"
  value       = aws_iam_role.login_service.arn
}

output "users_service_role_arn" {
  description = "IRSA role ARN for the users-service pods"
  value       = aws_iam_role.users_service.arn
}
