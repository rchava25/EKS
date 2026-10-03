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

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name    = "${var.project}-nonprod-nat-eip"
    Project = var.project
  }

  depends_on = [aws_internet_gateway.shared]
}

# One NAT Gateway in AZ-a; both private route tables route through it (regional mode).
resource "aws_nat_gateway" "regional" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id

  tags = {
    Name    = "${var.project}-nonprod-nat-gw"
    Project = var.project
  }

  depends_on = [aws_internet_gateway.shared]
}

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

# Single route table shared by both private subnets — both AZs egress via the one NAT GW.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.shared.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.regional.id
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
