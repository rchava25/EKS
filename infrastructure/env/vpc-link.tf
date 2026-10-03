resource "aws_security_group" "vpc_link" {
  name   = "${local.prefix}-vpc-link-sg"
  vpc_id = local.vpc_id

  egress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  tags = {
    Name    = "${local.prefix}-vpc-link-sg"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_apigatewayv2_vpc_link" "vpc_link" {
  name               = "${local.prefix}-vpc-link"
  security_group_ids = [aws_security_group.vpc_link.id]
  subnet_ids         = local.private_subnet_ids

  tags = {
    Name    = "${local.prefix}-vpc-link"
    Project = "anycompany-users"
    Env     = var.env
  }
}

output "vpc_link_id" {
  description = "API Gateway VPC Link V2 ID"
  value       = aws_apigatewayv2_vpc_link.vpc_link.id
}
