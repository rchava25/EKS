resource "kubernetes_namespace" "env" {
  metadata {
    name = local.prefix
    labels = {
      env     = var.env
      project = "anycompany-users"
    }
  }
}

resource "kubernetes_service_account" "login_service" {
  metadata {
    name      = "login-service"
    namespace = kubernetes_namespace.env.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.login_service.arn
    }
  }
}

resource "kubernetes_service_account" "users_service" {
  metadata {
    name      = "users-service"
    namespace = kubernetes_namespace.env.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.users_service.arn
    }
  }
}

# Deny all ingress from pods in other namespaces; allow same-namespace traffic only.
resource "kubernetes_network_policy" "deny_cross_namespace" {
  metadata {
    name      = "deny-cross-namespace"
    namespace = kubernetes_namespace.env.metadata[0].name
  }

  spec {
    pod_selector {}

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = kubernetes_namespace.env.metadata[0].name
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}

resource "kubernetes_config_map" "env_config" {
  metadata {
    name      = "anycompany-users-config"
    namespace = kubernetes_namespace.env.metadata[0].name
  }

  data = {
    TABLE_NAME           = aws_dynamodb_table.users.name
    COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.app.id
    COGNITO_USER_POOL_ID = aws_cognito_user_pool.main.id
    AWS_REGION           = var.aws_region
  }
}
