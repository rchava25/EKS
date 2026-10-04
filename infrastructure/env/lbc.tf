# AWS Load Balancer Controller is built-in to EKS Auto Mode.
# kubernetes_network_config.elastic_load_balancing.enabled = true in eks.tf
# activates it — no Helm release, no IAM role, no Pod Identity needed.
#
# TargetGroupBinding CRD is available automatically.
# Ingress resources are reconciled by the built-in LBC.
