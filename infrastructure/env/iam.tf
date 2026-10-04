# ── login-service IAM Role (Pod Identity) ────────────────────────────────────
# Trusted by pods.eks.amazonaws.com — no per-cluster OIDC conditions needed.

resource "aws_iam_role" "login_service" {
  name = "${local.prefix}-login-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
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

# Bind the role to login-service pods in this namespace via Pod Identity.
resource "aws_eks_pod_identity_association" "login_service" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = kubernetes_namespace.env.metadata[0].name
  service_account = "login-service"
  role_arn        = aws_iam_role.login_service.arn
}

# ── users-service IAM Role (Pod Identity) ────────────────────────────────────

resource "aws_iam_role" "users_service" {
  name = "${local.prefix}-users-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
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
      Resource = [
        aws_dynamodb_table.users.arn,
        "${aws_dynamodb_table.users.arn}/index/*",
      ]
    }]
  })
}

# Bind the role to users-service pods in this namespace via Pod Identity.
resource "aws_eks_pod_identity_association" "users_service" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = kubernetes_namespace.env.metadata[0].name
  service_account = "users-service"
  role_arn        = aws_iam_role.users_service.arn
}

output "login_service_role_arn" {
  description = "Pod Identity role ARN for the login-service pods"
  value       = aws_iam_role.login_service.arn
}

output "users_service_role_arn" {
  description = "Pod Identity role ARN for the users-service pods"
  value       = aws_iam_role.users_service.arn
}
