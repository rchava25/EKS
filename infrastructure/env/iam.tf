# ── ECS Task Roles ────────────────────────────────────────────────────────────
# One role per service — least-privilege access to AWS resources.
# Trust: ecs-tasks.amazonaws.com for Fargate task credentials.

locals {
  ecs_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# ── login-service ─────────────────────────────────────────────────────────────

resource "aws_iam_role" "login_service" {
  name               = "${local.prefix}-login-service-role"
  assume_role_policy = local.ecs_trust

  tags = {
    Name    = "${local.prefix}-login-service-role"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_iam_role_policy" "login_service_cognito" {
  name = "cognito-auth"
  role = aws_iam_role.login_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["cognito-idp:InitiateAuth", "cognito-idp:GlobalSignOut"]
      Resource = aws_cognito_user_pool.main.arn
    }]
  })
}

# ── users-service ─────────────────────────────────────────────────────────────

resource "aws_iam_role" "users_service" {
  name               = "${local.prefix}-users-service-role"
  assume_role_policy = local.ecs_trust

  tags = {
    Name    = "${local.prefix}-users-service-role"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_iam_role_policy" "users_service_dynamodb" {
  name = "dynamodb-crud"
  role = aws_iam_role.users_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem",
        "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:Scan",
      ]
      Resource = [
        aws_dynamodb_table.users.arn,
        "${aws_dynamodb_table.users.arn}/index/*",
      ]
    }]
  })
}

# ── browse-service ────────────────────────────────────────────────────────────

resource "aws_iam_role" "browse_service" {
  name               = "${local.prefix}-browse-service-role"
  assume_role_policy = local.ecs_trust

  tags = {
    Name    = "${local.prefix}-browse-service-role"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_iam_role_policy" "browse_service_dynamodb" {
  name = "dynamodb-read"
  role = aws_iam_role.browse_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
      Resource = [
        aws_dynamodb_table.products.arn,
        "${aws_dynamodb_table.products.arn}/index/*",
      ]
    }]
  })
}

# ── search-service ────────────────────────────────────────────────────────────

resource "aws_iam_role" "search_service" {
  name               = "${local.prefix}-search-service-role"
  assume_role_policy = local.ecs_trust

  tags = {
    Name    = "${local.prefix}-search-service-role"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_iam_role_policy" "search_service_opensearch" {
  name = "opensearch-http"
  role = aws_iam_role.search_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["es:ESHttp*"]
      Resource = "${aws_opensearch_domain.search.arn}/*"
    }]
  })
}

# ── payment-service ───────────────────────────────────────────────────────────

resource "aws_iam_role" "payment_service" {
  name               = "${local.prefix}-payment-service-role"
  assume_role_policy = local.ecs_trust

  tags = {
    Name    = "${local.prefix}-payment-service-role"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_iam_role_policy" "payment_service_dynamodb" {
  name = "dynamodb-crud"
  role = aws_iam_role.payment_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem",
        "dynamodb:Query", "dynamodb:Scan",
      ]
      Resource = [
        aws_dynamodb_table.orders.arn,
        "${aws_dynamodb_table.orders.arn}/index/*",
      ]
    }]
  })
}

resource "aws_iam_role_policy" "payment_service_sqs" {
  name = "sqs-publish"
  role = aws_iam_role.payment_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage", "sqs:GetQueueUrl"]
      Resource = aws_sqs_queue.shipping_dispatch.arn
    }]
  })
}

# ── shipping-service ──────────────────────────────────────────────────────────

resource "aws_iam_role" "shipping_service" {
  name               = "${local.prefix}-shipping-service-role"
  assume_role_policy = local.ecs_trust

  tags = {
    Name    = "${local.prefix}-shipping-service-role"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_iam_role_policy" "shipping_service_dynamodb" {
  name = "dynamodb-crud"
  role = aws_iam_role.shipping_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Query",
      ]
      Resource = aws_dynamodb_table.shipments.arn
    }]
  })
}

resource "aws_iam_role_policy" "shipping_service_sqs" {
  name = "sqs-consume"
  role = aws_iam_role.shipping_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
      Resource = aws_sqs_queue.shipping_dispatch.arn
    }]
  })
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "login_service_role_arn"    { value = aws_iam_role.login_service.arn }
output "users_service_role_arn"    { value = aws_iam_role.users_service.arn }
output "browse_service_role_arn"   { value = aws_iam_role.browse_service.arn }
output "search_service_role_arn"   { value = aws_iam_role.search_service.arn }
output "payment_service_role_arn"  { value = aws_iam_role.payment_service.arn }
output "shipping_service_role_arn" { value = aws_iam_role.shipping_service.arn }
