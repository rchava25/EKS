# ── EKS Cluster IAM Role ──────────────────────────────────────────────────────

resource "aws_iam_role" "eks_cluster" {
  name = "${local.prefix}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = {
    Name    = "${local.prefix}-eks-cluster-role"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name                          = "${local.prefix}-cluster"
  role_arn                      = aws_iam_role.eks_cluster.arn
  version                       = var.kubernetes_version
  bootstrap_self_managed_addons = false

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = local.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]

  tags = {
    Name    = "${local.prefix}-cluster"
    Project = "anycompany-users"
    Env     = var.env
  }
}

# ── Node Group IAM Role ───────────────────────────────────────────────────────

resource "aws_iam_role" "eks_nodes" {
  name = "${local.prefix}-eks-nodes-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name    = "${local.prefix}-eks-nodes-role"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_read" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ── Managed Node Group ────────────────────────────────────────────────────────

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.prefix}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = local.private_subnet_ids
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 4
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.eks_ecr_read,
  ]

  tags = {
    Name    = "${local.prefix}-nodes"
    Project = "anycompany-users"
    Env     = var.env
  }
}

# ── EKS Access Entries — console / ops principals ────────────────────────────
# Grant cluster-admin to any IAM ARNs passed via eks_admin_iam_arns.
# Use for AWS console users, ops roles, and CI roles that need kubectl access.

resource "aws_eks_access_entry" "admins" {
  for_each = toset(var.eks_admin_iam_arns)

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admins" {
  for_each = toset(var.eks_admin_iam_arns)

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admins]
}

# ── Pod Identity Agent addon ──────────────────────────────────────────────────
# Replaces IRSA. No per-cluster OIDC provider needed.
# Pod Identity agent runs as a DaemonSet and intercepts credential requests
# from pods, returning short-lived tokens scoped to the associated IAM role.

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"

  depends_on = [aws_eks_node_group.main]

  tags = {
    Name    = "${local.prefix}-pod-identity-agent"
    Project = "anycompany-users"
    Env     = var.env
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint — pass as var.eks_cluster_endpoint on second apply"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_ca_cert" {
  description = "EKS cluster CA cert (base64) — pass as var.eks_cluster_ca_cert on second apply"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}
