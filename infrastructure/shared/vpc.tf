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

# ── Zonal NAT Gateways — one per AZ ──────────────────────────────────────────
# Each private subnet routes through its local NAT gateway, eliminating
# cross-AZ data transfer charges ($0.01/GB each way) and removing the
# single-point-of-failure of a shared NAT in one AZ.

resource "aws_eip" "nat_a" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.shared]

  tags = {
    Name    = "${var.project}-nonprod-nat-eip-a"
    Project = var.project
  }
}

resource "aws_eip" "nat_b" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.shared]

  tags = {
    Name    = "${var.project}-nonprod-nat-eip-b"
    Project = var.project
  }
}

resource "aws_nat_gateway" "az_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.shared]

  tags = {
    Name    = "${var.project}-nonprod-nat-gw-a"
    Project = var.project
  }
}

resource "aws_nat_gateway" "az_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.public_b.id
  depends_on    = [aws_internet_gateway.shared]

  tags = {
    Name    = "${var.project}-nonprod-nat-gw-b"
    Project = var.project
  }
}

# ── Public route table ────────────────────────────────────────────────────────

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

# ── Per-AZ private route tables ───────────────────────────────────────────────
# Split into two tables so each subnet routes through its local NAT gateway.

resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.shared.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.az_a.id
  }

  tags = {
    Name    = "${var.project}-nonprod-private-rt-a"
    Project = var.project
  }
}

resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.shared.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.az_b.id
  }

  tags = {
    Name    = "${var.project}-nonprod-private-rt-b"
    Project = var.project
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_b.id
}

# ── VPC Gateway Endpoints — S3 and DynamoDB ───────────────────────────────────
# Gateway endpoints are free and route S3/DynamoDB traffic entirely within
# AWS's network — pods never hit the NAT gateway for these services.
# S3 is needed for ECR image layer pulls (ECR stores layers in S3).
# DynamoDB is the app's primary data store.

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.shared.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_a.id, aws_route_table.private_b.id]

  tags = {
    Name    = "${var.project}-nonprod-s3-endpoint"
    Project = var.project
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.shared.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_a.id, aws_route_table.private_b.id]

  tags = {
    Name    = "${var.project}-nonprod-dynamodb-endpoint"
    Project = var.project
  }
}
