data "aws_availability_zones" "available" {
  state = "available"
}

# Shared VPC lookup — used by dev and mr-* environments.
data "aws_vpc" "shared" {
  count = local.is_shared_vpc ? 1 : 0
  tags  = { Name = "anycompany-nonprod-shared-vpc" }
}

data "aws_subnets" "shared_private" {
  count = local.is_shared_vpc ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared[0].id]
  }

  tags = { Tier = "private" }
}

data "aws_subnets" "shared_public" {
  count = local.is_shared_vpc ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared[0].id]
  }

  tags = { Tier = "public" }
}

locals {
  # True for dev and any mr-* environment; false for preprod/prod (which get a dedicated VPC).
  is_shared_vpc = var.env == "dev" || startswith(var.env, "mr")

  # Unified VPC ID — resolves to the shared VPC (dev/mr) or the dedicated VPC (preprod/prod).
  # one() returns null when count=0, so the unused branch is safe.
  vpc_id = local.is_shared_vpc ? one(data.aws_vpc.shared[*].id) : one(aws_vpc.dedicated[*].id)

  private_subnet_ids = local.is_shared_vpc ? tolist(one(data.aws_subnets.shared_private[*].ids)) : [
    one(aws_subnet.dedicated_private_a[*].id),
    one(aws_subnet.dedicated_private_b[*].id),
  ]

  public_subnet_ids = local.is_shared_vpc ? tolist(one(data.aws_subnets.shared_public[*].ids)) : [
    one(aws_subnet.dedicated_public_a[*].id),
    one(aws_subnet.dedicated_public_b[*].id),
  ]
}
