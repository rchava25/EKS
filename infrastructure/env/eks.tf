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

# Base EKS cluster policy + Auto Mode policies for compute/storage/networking/LB.
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_compute_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSComputePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_block_storage_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_load_balancing_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_networking_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy"
}

# ── Node IAM Role (used by Auto Mode — no managed node group needed) ──────────
# Auto Mode uses minimal policies: WorkerNodeMinimal + ECR pull-only.

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

resource "aws_iam_role_policy_attachment" "eks_worker_node_minimal" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_pull_only" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

# ── EKS Cluster — Auto Mode ───────────────────────────────────────────────────
# Auto Mode delegates node provisioning, patching, LBC, EBS CSI, VPC CNI,
# CoreDNS, and kube-proxy to AWS. No managed node groups, no addon installs.

resource "aws_eks_cluster" "main" {
  name                          = "${local.prefix}-cluster"
  role_arn                      = aws_iam_role.eks_cluster.arn
  version                       = var.kubernetes_version
  bootstrap_self_managed_addons = false

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Auto Mode: AWS provisions and patches nodes from general-purpose NodePool.
  compute_config {
    enabled       = true
    node_role_arn = aws_iam_role.eks_nodes.arn
    node_pools    = ["general-purpose"]
  }

  # Auto Mode: AWS manages EBS CSI driver and default StorageClass.
  storage_config {
    block_storage {
      enabled = true
    }
  }

  # Auto Mode: AWS manages AWS LBC for Ingress + TargetGroupBinding.
  kubernetes_network_config {
    elastic_load_balancing {
      enabled = true
    }
  }

  vpc_config {
    subnet_ids              = local.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_compute_policy,
    aws_iam_role_policy_attachment.eks_block_storage_policy,
    aws_iam_role_policy_attachment.eks_load_balancing_policy,
    aws_iam_role_policy_attachment.eks_networking_policy,
  ]

  tags = {
    Name    = "${local.prefix}-cluster"
    Project = "anycompany-users"
    Env     = var.env
  }
}

# ── EKS Access Entries — console / ops principals ────────────────────────────

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

# ── Outputs ───────────────────────────────────────────────────────────────────

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_ca_cert" {
  description = "EKS cluster CA cert (base64)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}
