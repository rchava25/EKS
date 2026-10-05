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

variable "task_cpu" {
  description = "ECS task CPU units (256=0.25vCPU, 512=0.5vCPU, 1024=1vCPU)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "ECS task memory in MB"
  type        = number
  default     = 512
}
