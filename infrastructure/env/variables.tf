variable "env" {
  description = "Environment name: dev | mr-<N> | preprod | prod"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "nat_gateway_mode" {
  description = "regional = one NAT GW per VPC (default); zonal = one per AZ (preprod/prod only)"
  type        = string
  default     = "regional"

  validation {
    condition     = contains(["regional", "zonal"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode must be 'regional' or 'zonal'."
  }
}

variable "create_ecr" {
  description = "Create ECR repos. True for dev only; MR/preprod/prod share the dev repos."
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "CIDR block for dedicated VPC (preprod/prod only; ignored for dev/mr)"
  type        = string
  default     = "10.2.0.0/16"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Increment one minor version at a time — AWS rejects multi-version skips."
  type        = string
  default     = "1.31"
}

variable "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint — empty on first apply; populated by CI from Terraform outputs for second apply that creates kubernetes resources"
  type        = string
  default     = ""
}

variable "eks_cluster_ca_cert" {
  description = "EKS cluster CA certificate (base64) — empty on first apply; populated by CI from Terraform outputs"
  type        = string
  default     = ""
  sensitive   = true
}

variable "eks_admin_iam_arns" {
  description = "List of IAM user/role ARNs to grant EKS cluster-admin access (console, ops, etc.)"
  type        = list(string)
  default     = []
}
