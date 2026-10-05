# ── Secrets Manager — per-service runtime configuration ──────────────────────
# ECS task definitions reference these via valueFrom (secrets injection).
# The ECS execution role has GetSecretValue on all ${local.prefix}-* secrets.

locals {
  service_secrets = {
    users-service = jsonencode({
      table_name = aws_dynamodb_table.users.name
      aws_region = var.aws_region
    })
    login-service = jsonencode({
      user_pool_id = aws_cognito_user_pool.main.id
      client_id    = aws_cognito_user_pool_client.app.id
      aws_region   = var.aws_region
    })
    browse-service = jsonencode({
      table_name = aws_dynamodb_table.products.name
      redis_host = aws_elasticache_cluster.browse.cache_nodes[0].address
      redis_port = tostring(aws_elasticache_cluster.browse.port)
      aws_region = var.aws_region
    })
    search-service = jsonencode({
      opensearch_host  = "https://${aws_opensearch_domain.search.endpoint}"
      opensearch_index = "products"
      aws_region       = var.aws_region
    })
    payment-service = jsonencode({
      orders_table              = aws_dynamodb_table.orders.name
      shipping_dispatch_queue   = aws_sqs_queue.shipping_dispatch.url
      payment_events_queue      = aws_sqs_queue.payment_events.url
      aws_region                = var.aws_region
    })
    shipping-service = jsonencode({
      shipments_table      = aws_dynamodb_table.shipments.name
      shipping_queue_url   = aws_sqs_queue.shipping_dispatch.url
      aws_region           = var.aws_region
    })
  }
}

resource "aws_secretsmanager_secret" "services" {
  for_each                = local.service_secrets
  name                    = "${local.prefix}-${each.key}"
  description             = "Runtime config for ${each.key}"
  recovery_window_in_days = 0

  tags = {
    Name    = "${local.prefix}-${each.key}"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_secretsmanager_secret_version" "services" {
  for_each      = local.service_secrets
  secret_id     = aws_secretsmanager_secret.services[each.key].id
  secret_string = each.value
}

output "secret_arns" {
  description = "Secrets Manager ARNs keyed by service"
  value       = { for k, s in aws_secretsmanager_secret.services : k => s.arn }
}
