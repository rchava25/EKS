# ── Vertical Pod Autoscaler ───────────────────────────────────────────────────
# Observes actual CPU/memory consumption and recommends (or auto-sets)
# container resource requests. Deployed in "Off" mode (recommendation only)
# so it never restarts pods unprompted — review recommendations in the
# VPA status field and tune requests/limits accordingly.
#
# Query recommendations:
#   kubectl get vpa -n <ns> -o jsonpath='{.items[*].status.recommendation}'

resource "helm_release" "vpa" {
  name             = "vpa"
  repository       = "https://charts.fairwinds.com/stable"
  chart            = "vpa"
  namespace        = "kube-system"
  version          = "4.4.6"
  wait             = true

  set {
    name  = "admissionController.enabled"
    value = "false"
  }
  set {
    name  = "updater.enabled"
    value = "false"
  }

  depends_on = [aws_eks_cluster.main]
}
