# ── Secrets Manager — app configuration secrets ───────────────────────────────
# Replaces plain-text env vars in Deployment manifests.
# External Secrets Operator (eso.tf) syncs these into K8s Secrets automatically.

resource "aws_secretsmanager_secret" "users_service" {
  name                    = "${local.prefix}-users-service"
  description             = "Runtime config for users-service pods"
  recovery_window_in_days = 0

  tags = {
    Name    = "${local.prefix}-users-service"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_secretsmanager_secret_version" "users_service" {
  secret_id = aws_secretsmanager_secret.users_service.id
  secret_string = jsonencode({
    table_name = aws_dynamodb_table.users.name
    aws_region = var.aws_region
  })
}

resource "aws_secretsmanager_secret" "login_service" {
  name                    = "${local.prefix}-login-service"
  description             = "Runtime config for login-service pods"
  recovery_window_in_days = 0

  tags = {
    Name    = "${local.prefix}-login-service"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_secretsmanager_secret_version" "login_service" {
  secret_id = aws_secretsmanager_secret.login_service.id
  secret_string = jsonencode({
    user_pool_id = aws_cognito_user_pool.main.id
    client_id    = aws_cognito_user_pool_client.main.id
    aws_region   = var.aws_region
  })
}

# Grant app roles read access to their own secrets only.
resource "aws_iam_role_policy" "users_service_secrets" {
  name = "${local.prefix}-users-secrets-read"
  role = aws_iam_role.users_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      Resource = aws_secretsmanager_secret.users_service.arn
    }]
  })
}

resource "aws_iam_role_policy" "login_service_secrets" {
  name = "${local.prefix}-login-secrets-read"
  role = aws_iam_role.login_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      Resource = aws_secretsmanager_secret.login_service.arn
    }]
  })
}

output "users_service_secret_arn" {
  value = aws_secretsmanager_secret.users_service.arn
}

output "login_service_secret_arn" {
  value = aws_secretsmanager_secret.login_service.arn
}
