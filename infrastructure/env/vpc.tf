# Dedicated VPC resources — only created for preprod and prod.
# dev and mr-* environments use the shared VPC looked up in data.tf.

locals {
  # Number of NAT Gateways: 1 (regional) or 2 (zonal, one per AZ).
  nat_count = !local.is_shared_vpc ? (var.nat_gateway_mode == "zonal" ? 2 : 1) : 0
}

resource "aws_vpc" "dedicated" {
  count                = local.is_shared_vpc ? 0 : 1
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${local.prefix}-vpc"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_subnet" "dedicated_public_a" {
  count                   = local.is_shared_vpc ? 0 : 1
  vpc_id                  = aws_vpc.dedicated[0].id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 0)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.prefix}-public-a"
    Tier = "public"
    Env  = var.env
  }
}

resource "aws_subnet" "dedicated_public_b" {
  count                   = local.is_shared_vpc ? 0 : 1
  vpc_id                  = aws_vpc.dedicated[0].id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.prefix}-public-b"
    Tier = "public"
    Env  = var.env
  }
}

resource "aws_subnet" "dedicated_private_a" {
  count             = local.is_shared_vpc ? 0 : 1
  vpc_id            = aws_vpc.dedicated[0].id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 10)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${local.prefix}-private-a"
    Tier = "private"
    Env  = var.env
  }
}

resource "aws_subnet" "dedicated_private_b" {
  count             = local.is_shared_vpc ? 0 : 1
  vpc_id            = aws_vpc.dedicated[0].id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 11)
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${local.prefix}-private-b"
    Tier = "private"
    Env  = var.env
  }
}

resource "aws_internet_gateway" "dedicated" {
  count  = local.is_shared_vpc ? 0 : 1
  vpc_id = aws_vpc.dedicated[0].id

  tags = {
    Name = "${local.prefix}-igw"
    Env  = var.env
  }
}

resource "aws_eip" "dedicated_nat" {
  count  = local.nat_count
  domain = "vpc"

  tags = {
    Name = "${local.prefix}-nat-eip-${count.index}"
    Env  = var.env
  }

  depends_on = [aws_internet_gateway.dedicated]
}

# Regional mode: 1 NAT GW in AZ-a, both private subnets route through it.
# Zonal mode:   2 NAT GWs (AZ-a and AZ-b), each private subnet uses its own.
resource "aws_nat_gateway" "dedicated" {
  count         = local.nat_count
  allocation_id = aws_eip.dedicated_nat[count.index].id
  subnet_id = count.index == 0 ? aws_subnet.dedicated_public_a[0].id : aws_subnet.dedicated_public_b[0].id

  tags = {
    Name = "${local.prefix}-nat-gw-${count.index}"
    Env  = var.env
  }

  depends_on = [aws_internet_gateway.dedicated]
}

resource "aws_route_table" "dedicated_public" {
  count  = local.is_shared_vpc ? 0 : 1
  vpc_id = aws_vpc.dedicated[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dedicated[0].id
  }

  tags = {
    Name = "${local.prefix}-public-rt"
    Env  = var.env
  }
}

resource "aws_route_table_association" "dedicated_public_a" {
  count          = local.is_shared_vpc ? 0 : 1
  subnet_id      = aws_subnet.dedicated_public_a[0].id
  route_table_id = aws_route_table.dedicated_public[0].id
}

resource "aws_route_table_association" "dedicated_public_b" {
  count          = local.is_shared_vpc ? 0 : 1
  subnet_id      = aws_subnet.dedicated_public_b[0].id
  route_table_id = aws_route_table.dedicated_public[0].id
}

# One private route table per NAT GW.
resource "aws_route_table" "dedicated_private" {
  count  = local.nat_count
  vpc_id = aws_vpc.dedicated[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.dedicated[count.index].id
  }

  tags = {
    Name = "${local.prefix}-private-rt-${count.index}"
    Env  = var.env
  }
}

resource "aws_route_table_association" "dedicated_private_a" {
  count          = local.is_shared_vpc ? 0 : 1
  subnet_id      = aws_subnet.dedicated_private_a[0].id
  route_table_id = aws_route_table.dedicated_private[0].id
}

resource "aws_route_table_association" "dedicated_private_b" {
  count          = local.is_shared_vpc ? 0 : 1
  subnet_id      = aws_subnet.dedicated_private_b[0].id
  # Zonal: AZ-b uses its own NAT GW (index 1). Regional: both use the single NAT GW (index 0).
  route_table_id = aws_route_table.dedicated_private[var.nat_gateway_mode == "zonal" ? 1 : 0].id
}
