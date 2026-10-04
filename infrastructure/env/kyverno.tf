# ── Kyverno — Policy Engine ───────────────────────────────────────────────────
# Enforces cluster-wide security and operational standards as K8s-native policies.
# Policies in k8s/kyverno-policies.yaml run in Audit mode (report only) by default.
# Change validationFailureAction to Enforce once teams are aware of the rules.

resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno/"
  chart            = "kyverno"
  namespace        = "kyverno"
  create_namespace = true
  version          = "3.2.7"
  wait             = true

  set {
    name  = "replicaCount"
    value = "1"
  }
  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "resources.requests.memory"
    value = "128Mi"
  }
  set {
    name  = "resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "resources.limits.memory"
    value = "512Mi"
  }

  depends_on = [aws_eks_cluster.main]
}
