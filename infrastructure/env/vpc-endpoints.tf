# VPC endpoints — allow ECS Fargate tasks in private subnets to reach AWS APIs
# without a NAT Gateway.

# For the shared VPC (dev/mr) look up the private route tables by subnet association.
data "aws_route_tables" "shared_private" {
  count  = local.is_shared_vpc ? 1 : 0
  vpc_id = local.vpc_id

  filter {
    name   = "association.subnet-id"
    values = local.private_subnet_ids
  }
}

locals {
  private_route_table_ids = local.is_shared_vpc ? tolist(one(data.aws_route_tables.shared_private[*].ids)) : [
    for rt in aws_route_table.dedicated_private : rt.id
  ]

  interface_endpoint_services = [
    "ecr.dkr",
    "ecr.api",
    "secretsmanager",
    "logs",
    "sts",
  ]
}

# S3 Gateway endpoint — free, required by ECR to pull image layers.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.private_route_table_ids

  tags = {
    Name    = "${local.prefix}-s3-endpoint"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_security_group" "vpc_endpoints" {
  name   = "${local.prefix}-vpc-endpoints-sg"
  vpc_id = local.vpc_id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${local.prefix}-vpc-endpoints-sg"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoint_services)

  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name    = "${local.prefix}-${each.value}-endpoint"
    Project = "anycompany-users"
    Env     = var.env
  }
}
