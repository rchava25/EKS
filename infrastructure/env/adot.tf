# ── AWS Distro for OpenTelemetry (ADOT) ──────────────────────────────────────
# Installs the ADOT Collector operator as an EKS addon.
# Once installed, deploy an OpenTelemetryCollector CR (k8s/adot-collector.yaml)
# to route traces → AWS X-Ray and metrics → CloudWatch.

resource "aws_iam_role" "adot" {
  name = "${local.prefix}-adot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })

  tags = {
    Name    = "${local.prefix}-adot-role"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_iam_role_policy_attachment" "adot_xray" {
  role       = aws_iam_role.adot.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy_attachment" "adot_cloudwatch" {
  role       = aws_iam_role.adot.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_eks_pod_identity_association" "adot" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "opentelemetry-operator-system"
  service_account = "opentelemetry-operator"
  role_arn        = aws_iam_role.adot.arn
}

resource "aws_eks_addon" "adot" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "adot"
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [aws_eks_cluster.main, aws_eks_pod_identity_association.adot]

  tags = {
    Name    = "${local.prefix}-adot"
    Project = "anycompany-users"
    Env     = var.env
  }
}

output "adot_role_arn" {
  value = aws_iam_role.adot.arn
}
