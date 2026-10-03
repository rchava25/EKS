terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  # Bucket and region supplied via -backend-config at init time.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

# Cluster endpoint and CA cert are empty on the first apply (cluster not yet created).
# CI populates them from Terraform outputs and re-applies to create kubernetes resources.
provider "kubernetes" {
  host                   = var.eks_cluster_endpoint
  cluster_ca_certificate = var.eks_cluster_ca_cert != "" ? base64decode(var.eks_cluster_ca_cert) : null
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", "anycompany-users-${var.env}-cluster", "--region", var.aws_region]
  }
}
