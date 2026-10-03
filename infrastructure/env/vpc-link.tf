resource "aws_api_gateway_vpc_link" "vpc_link" {
  name        = "${local.prefix}-vpc-link"
  target_arns = [aws_lb.nlb.arn]

  tags = {
    Name    = "${local.prefix}-vpc-link"
    Project = "anycompany-users"
    Env     = var.env
  }
}

output "vpc_link_id" {
  description = "API Gateway VPC Link ID"
  value       = aws_api_gateway_vpc_link.vpc_link.id
}
