# ECR repos are shared across all non-prod environments (dev + all mr-*).
# Created once when create_ecr = true (dev only); preprod/prod look them up.

locals {
  service_names = ["login-service", "users-service", "browse-service", "search-service", "payment-service", "shipping-service"]
}

resource "aws_ecr_repository" "services" {
  for_each             = var.create_ecr ? toset(local.service_names) : toset([])
  name                 = "anycompany-${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name    = "anycompany-${each.key}"
    Project = "anycompany-users"
  }
}

resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = var.create_ecr ? toset(local.service_names) : toset([])
  repository = aws_ecr_repository.services[each.key].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Retain last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

data "aws_ecr_repository" "services" {
  for_each = var.create_ecr ? toset([]) : toset(local.service_names)
  name     = "anycompany-${each.key}"
}

locals {
  ecr_urls = {
    for s in local.service_names :
    s => var.create_ecr ? aws_ecr_repository.services[s].repository_url : data.aws_ecr_repository.services[s].repository_url
  }
}

output "ecr_urls" {
  description = "ECR repository URLs keyed by service name"
  value       = local.ecr_urls
}
