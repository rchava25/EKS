# ── Shipping dispatch queue ───────────────────────────────────────────────────
# payment-service publishes order-paid events; shipping-service consumes them.

resource "aws_sqs_queue" "shipping_dispatch_dlq" {
  name                      = "${local.prefix}-shipping-dispatch-dlq"
  message_retention_seconds = 1209600

  tags = {
    Name    = "${local.prefix}-shipping-dispatch-dlq"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_sqs_queue" "shipping_dispatch" {
  name                       = "${local.prefix}-shipping-dispatch"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.shipping_dispatch_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name    = "${local.prefix}-shipping-dispatch"
    Project = "anycompany-users"
    Env     = var.env
  }
}

# ── Payment events queue ──────────────────────────────────────────────────────
# For future consumers (analytics, notifications) listening to payment events.

resource "aws_sqs_queue" "payment_events_dlq" {
  name                      = "${local.prefix}-payment-events-dlq"
  message_retention_seconds = 1209600

  tags = {
    Name    = "${local.prefix}-payment-events-dlq"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_sqs_queue" "payment_events" {
  name                       = "${local.prefix}-payment-events"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.payment_events_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name    = "${local.prefix}-payment-events"
    Project = "anycompany-users"
    Env     = var.env
  }
}

output "shipping_dispatch_queue_url" { value = aws_sqs_queue.shipping_dispatch.url }
output "shipping_dispatch_queue_arn" { value = aws_sqs_queue.shipping_dispatch.arn }
output "payment_events_queue_url"    { value = aws_sqs_queue.payment_events.url }
output "payment_events_queue_arn"    { value = aws_sqs_queue.payment_events.arn }
