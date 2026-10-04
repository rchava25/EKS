# ── External Secrets Operator ─────────────────────────────────────────────────
# Syncs AWS Secrets Manager secrets into K8s Secrets automatically.
# Eliminates plain-text env vars and removes need to update Deployments
# when secrets rotate — pods pick up new values on next refresh cycle.

resource "aws_iam_role" "eso" {
  name = "${local.prefix}-eso-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })

  tags = {
    Name    = "${local.prefix}-eso-role"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_iam_role_policy" "eso" {
  name = "eso-secretsmanager"
  role = aws_iam_role.eso.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecretVersionIds",
      ]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${local.prefix}-*"
    }]
  })
}

resource "aws_eks_pod_identity_association" "eso" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.eso.arn
}

resource "helm_release" "eso" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "0.10.3"
  wait             = true

  depends_on = [aws_eks_cluster.main, aws_eks_pod_identity_association.eso]
}

output "eso_role_arn" {
  value = aws_iam_role.eso.arn
}
