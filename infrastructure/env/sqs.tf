# ── SQS Queue — event-driven scaling trigger ──────────────────────────────────
# Enables KEDA to scale users-service based on queue depth instead of CPU.
# Producers push user-related events (imports, bulk updates) to this queue.
# KEDA ScaledObject (k8s/users-scaledobject-sqs.yaml) watches queue depth
# and scales replicas proportionally — reacts before CPU spikes, can scale to 0.

resource "aws_sqs_queue" "users_requests_dlq" {
  name                      = "${local.prefix}-users-requests-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Name    = "${local.prefix}-users-requests-dlq"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_sqs_queue" "users_requests" {
  name                       = "${local.prefix}-users-requests"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20 # long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.users_requests_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name    = "${local.prefix}-users-requests"
    Project = "anycompany-users"
    Env     = var.env
  }
}

# KEDA needs sqs:GetQueueAttributes + cloudwatch:GetMetricData to read queue depth.
resource "aws_iam_role" "keda_sqs" {
  name = "${local.prefix}-keda-sqs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })

  tags = {
    Name    = "${local.prefix}-keda-sqs-role"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_iam_role_policy" "keda_sqs" {
  name = "keda-sqs-read"
  role = aws_iam_role.keda_sqs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
        Resource = aws_sqs_queue.users_requests.arn
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:GetMetricData"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "keda_sqs" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "keda"
  service_account = "keda-operator"
  role_arn        = aws_iam_role.keda_sqs.arn
}

# Grant users-service permission to send messages to the queue.
resource "aws_iam_role_policy" "users_service_sqs" {
  name = "${local.prefix}-users-sqs-send"
  role = aws_iam_role.users_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage", "sqs:GetQueueUrl"]
      Resource = aws_sqs_queue.users_requests.arn
    }]
  })
}

output "users_requests_queue_url" {
  value = aws_sqs_queue.users_requests.url
}

output "users_requests_queue_arn" {
  value = aws_sqs_queue.users_requests.arn
}
