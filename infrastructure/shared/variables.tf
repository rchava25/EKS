variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix used for resource naming"
  type        = string
  default     = "anycompany-users"
}
