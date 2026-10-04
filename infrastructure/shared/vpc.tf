data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "shared" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "anycompany-nonprod-shared-vpc"
    Project = var.project
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.shared.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project}-nonprod-public-a"
    Project = var.project
    Tier    = "public"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.shared.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project}-nonprod-public-b"
    Project = var.project
    Tier    = "public"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.shared.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name    = "${var.project}-nonprod-private-a"
    Project = var.project
    Tier    = "private"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.shared.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name    = "${var.project}-nonprod-private-b"
    Project = var.project
    Tier    = "private"
  }
}

resource "aws_internet_gateway" "shared" {
  vpc_id = aws_vpc.shared.id

  tags = {
    Name    = "${var.project}-nonprod-igw"
    Project = var.project
  }
}

# ── NAT Gateway ───────────────────────────────────────────────────────────────
# Single NAT gateway — all private subnets route through it.
# Cheaper than per-AZ NATs: no cross-AZ data transfer charges for NAT traffic.

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.shared]

  tags = {
    Name    = "${var.project}-nonprod-nat-eip"
    Project = var.project
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.shared]

  tags = {
    Name    = "${var.project}-nonprod-nat-gw"
    Project = var.project
  }
}

# ── Route tables ──────────────────────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.shared.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.shared.id
  }

  tags = {
    Name    = "${var.project}-nonprod-public-rt"
    Project = var.project
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Single private route table — regional NAT serves both AZs.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.shared.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name    = "${var.project}-nonprod-private-rt"
    Project = var.project
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# ── VPC Gateway Endpoints — S3 and DynamoDB ───────────────────────────────────
# Free — S3/DynamoDB traffic stays within AWS network, never hits NAT.

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.shared.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name    = "${var.project}-nonprod-s3-endpoint"
    Project = var.project
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.shared.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name    = "${var.project}-nonprod-dynamodb-endpoint"
    Project = var.project
  }
}

# ── Interface VPC Endpoints — ECR, STS, Secrets Manager ──────────────────────
# Eliminates NAT cost for image pulls and AWS API calls from pods.
# ECR DKR: ~60-80% of NAT egress from EKS is Docker layer pulls.
# STS: every Pod Identity credential refresh hits STS — kept inside VPC.
# Secrets Manager: ESO polls every hour; keeps secrets traffic off NAT.

resource "aws_security_group" "vpc_endpoints" {
  name   = "${var.project}-nonprod-endpoints-sg"
  vpc_id = aws_vpc.shared.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.shared.cidr_block]
    description = "HTTPS from VPC"
  }

  tags = {
    Name    = "${var.project}-nonprod-endpoints-sg"
    Project = var.project
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.shared.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name    = "${var.project}-nonprod-ecr-api-endpoint"
    Project = var.project
  }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.shared.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name    = "${var.project}-nonprod-ecr-dkr-endpoint"
    Project = var.project
  }
}

resource "aws_vpc_endpoint" "sts" {
  vpc_id              = aws_vpc.shared.id
  service_name        = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name    = "${var.project}-nonprod-sts-endpoint"
    Project = var.project
  }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.shared.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name    = "${var.project}-nonprod-secretsmanager-endpoint"
    Project = var.project
  }
}
