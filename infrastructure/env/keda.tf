# ── KEDA — Kubernetes Event-driven Autoscaling ────────────────────────────────
# Replaces HPA with event-driven scaling. Supports CPU, memory, SQS, DynamoDB
# streams, custom Prometheus metrics — all via ScaledObject CRDs.

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  namespace        = "keda"
  create_namespace = true
  version          = "2.16.0"

  set {
    name  = "resources.operator.requests.cpu"
    value = "100m"
  }
  set {
    name  = "resources.operator.requests.memory"
    value = "128Mi"
  }
  set {
    name  = "resources.operator.limits.cpu"
    value = "200m"
  }
  set {
    name  = "resources.operator.limits.memory"
    value = "256Mi"
  }

  depends_on = [aws_eks_node_group.main, helm_release.lbc]
}
