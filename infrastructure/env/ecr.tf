# ECR repos are shared across all non-prod environments (dev + all mr-*).
# They are created once when create_ecr = true (dev only) and reused by MR environments.
# preprod and prod pull images from the non-prod repos, so create_ecr = false for those.

resource "aws_ecr_repository" "login_service" {
  count                = var.create_ecr ? 1 : 0
  name                 = "anycompany-login-service"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name    = "anycompany-login-service"
    Project = "anycompany-users"
  }
}

resource "aws_ecr_repository" "users_service" {
  count                = var.create_ecr ? 1 : 0
  name                 = "anycompany-users-service"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name    = "anycompany-users-service"
    Project = "anycompany-users"
  }
}

resource "aws_ecr_lifecycle_policy" "login_service" {
  count      = var.create_ecr ? 1 : 0
  repository = aws_ecr_repository.login_service[0].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Retain last 20 images; all envs share the same SHA tag"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "users_service" {
  count      = var.create_ecr ? 1 : 0
  repository = aws_ecr_repository.users_service[0].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Retain last 20 images; all envs share the same SHA tag"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

# Look up the repos when this env doesn't own them (mr, preprod, prod).
data "aws_ecr_repository" "login_service" {
  count = var.create_ecr ? 0 : 1
  name  = "anycompany-login-service"
}

data "aws_ecr_repository" "users_service" {
  count = var.create_ecr ? 0 : 1
  name  = "anycompany-users-service"
}

locals {
  login_ecr_url = var.create_ecr ? aws_ecr_repository.login_service[0].repository_url : data.aws_ecr_repository.login_service[0].repository_url
  users_ecr_url = var.create_ecr ? aws_ecr_repository.users_service[0].repository_url : data.aws_ecr_repository.users_service[0].repository_url
}

output "login_ecr_url" {
  description = "ECR URL for the login-service image"
  value       = local.login_ecr_url
}

output "users_ecr_url" {
  description = "ECR URL for the users-service image"
  value       = local.users_ecr_url
}
