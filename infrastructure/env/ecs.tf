# ── ECS Execution Role (shared across all services) ───────────────────────────
# Needed by Fargate to pull ECR images and inject Secrets Manager values.

resource "aws_iam_role" "ecs_execution" {
  name = "${local.prefix}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = {
    Name    = "${local.prefix}-ecs-execution-role"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "secrets-read"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${local.prefix}-*"
    }]
  })
}

# ── CloudWatch Log Groups ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "services" {
  for_each          = toset(["login-service", "users-service", "browse-service", "search-service", "payment-service", "shipping-service"])
  name              = "/ecs/${local.prefix}-${each.key}"
  retention_in_days = 14

  tags = {
    Name    = "/ecs/${local.prefix}-${each.key}"
    Project = "anycompany-users"
    Env     = var.env
  }
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "${local.prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name    = "${local.prefix}-cluster"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# ── Task Definitions ──────────────────────────────────────────────────────────

locals {
  log_config = {
    for svc in ["login-service", "users-service", "browse-service", "search-service", "payment-service", "shipping-service"] :
    svc => {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${local.prefix}-${svc}"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = svc
      }
    }
  }
}

resource "aws_ecs_task_definition" "login_service" {
  family                   = "${local.prefix}-login-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.login_service.arn

  container_definitions = jsonencode([{
    name      = "login-service"
    image     = "${local.ecr_urls["login-service"]}:latest"
    essential = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    secrets = [
      { name = "USER_POOL_ID", valueFrom = "${aws_secretsmanager_secret.services["login-service"].arn}:user_pool_id::" },
      { name = "CLIENT_ID",    valueFrom = "${aws_secretsmanager_secret.services["login-service"].arn}:client_id::" },
      { name = "AWS_REGION",   valueFrom = "${aws_secretsmanager_secret.services["login-service"].arn}:aws_region::" },
    ]
    logConfiguration = local.log_config["login-service"]
  }])
}

resource "aws_ecs_task_definition" "users_service" {
  family                   = "${local.prefix}-users-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.users_service.arn

  container_definitions = jsonencode([{
    name      = "users-service"
    image     = "${local.ecr_urls["users-service"]}:latest"
    essential = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    secrets = [
      { name = "TABLE_NAME", valueFrom = "${aws_secretsmanager_secret.services["users-service"].arn}:table_name::" },
      { name = "AWS_REGION", valueFrom = "${aws_secretsmanager_secret.services["users-service"].arn}:aws_region::" },
    ]
    logConfiguration = local.log_config["users-service"]
  }])
}

resource "aws_ecs_task_definition" "browse_service" {
  family                   = "${local.prefix}-browse-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.browse_service.arn

  container_definitions = jsonencode([{
    name      = "browse-service"
    image     = "${local.ecr_urls["browse-service"]}:latest"
    essential = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    secrets = [
      { name = "TABLE_NAME", valueFrom = "${aws_secretsmanager_secret.services["browse-service"].arn}:table_name::" },
      { name = "REDIS_HOST", valueFrom = "${aws_secretsmanager_secret.services["browse-service"].arn}:redis_host::" },
      { name = "REDIS_PORT", valueFrom = "${aws_secretsmanager_secret.services["browse-service"].arn}:redis_port::" },
      { name = "AWS_REGION", valueFrom = "${aws_secretsmanager_secret.services["browse-service"].arn}:aws_region::" },
    ]
    logConfiguration = local.log_config["browse-service"]
  }])
}

resource "aws_ecs_task_definition" "search_service" {
  family                   = "${local.prefix}-search-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.search_service.arn

  container_definitions = jsonencode([{
    name      = "search-service"
    image     = "${local.ecr_urls["search-service"]}:latest"
    essential = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    secrets = [
      { name = "OPENSEARCH_HOST",  valueFrom = "${aws_secretsmanager_secret.services["search-service"].arn}:opensearch_host::" },
      { name = "OPENSEARCH_INDEX", valueFrom = "${aws_secretsmanager_secret.services["search-service"].arn}:opensearch_index::" },
      { name = "AWS_REGION",       valueFrom = "${aws_secretsmanager_secret.services["search-service"].arn}:aws_region::" },
    ]
    logConfiguration = local.log_config["search-service"]
  }])
}

resource "aws_ecs_task_definition" "payment_service" {
  family                   = "${local.prefix}-payment-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.payment_service.arn

  container_definitions = jsonencode([{
    name      = "payment-service"
    image     = "${local.ecr_urls["payment-service"]}:latest"
    essential = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    secrets = [
      { name = "ORDERS_TABLE",            valueFrom = "${aws_secretsmanager_secret.services["payment-service"].arn}:orders_table::" },
      { name = "SHIPPING_DISPATCH_QUEUE", valueFrom = "${aws_secretsmanager_secret.services["payment-service"].arn}:shipping_dispatch_queue::" },
      { name = "PAYMENT_EVENTS_QUEUE",    valueFrom = "${aws_secretsmanager_secret.services["payment-service"].arn}:payment_events_queue::" },
      { name = "AWS_REGION",              valueFrom = "${aws_secretsmanager_secret.services["payment-service"].arn}:aws_region::" },
    ]
    logConfiguration = local.log_config["payment-service"]
  }])
}

resource "aws_ecs_task_definition" "shipping_service" {
  family                   = "${local.prefix}-shipping-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.shipping_service.arn

  container_definitions = jsonencode([{
    name      = "shipping-service"
    image     = "${local.ecr_urls["shipping-service"]}:latest"
    essential = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    secrets = [
      { name = "SHIPMENTS_TABLE",    valueFrom = "${aws_secretsmanager_secret.services["shipping-service"].arn}:shipments_table::" },
      { name = "SHIPPING_QUEUE_URL", valueFrom = "${aws_secretsmanager_secret.services["shipping-service"].arn}:shipping_queue_url::" },
      { name = "AWS_REGION",         valueFrom = "${aws_secretsmanager_secret.services["shipping-service"].arn}:aws_region::" },
    ]
    logConfiguration = local.log_config["shipping-service"]
  }])
}

# ── ECS Services ──────────────────────────────────────────────────────────────

locals {
  ecs_service_defs = {
    login    = { task_def = aws_ecs_task_definition.login_service.arn,    tg_key = "login" }
    users    = { task_def = aws_ecs_task_definition.users_service.arn,    tg_key = "users" }
    browse   = { task_def = aws_ecs_task_definition.browse_service.arn,   tg_key = "browse" }
    search   = { task_def = aws_ecs_task_definition.search_service.arn,   tg_key = "search" }
    payment  = { task_def = aws_ecs_task_definition.payment_service.arn,  tg_key = "payment" }
    shipping = { task_def = aws_ecs_task_definition.shipping_service.arn, tg_key = "shipping" }
  }

  svc_container_names = {
    login    = "login-service"
    users    = "users-service"
    browse   = "browse-service"
    search   = "search-service"
    payment  = "payment-service"
    shipping = "shipping-service"
  }
}

resource "aws_ecs_service" "services" {
  for_each = local.ecs_service_defs

  name                               = "${local.prefix}-${each.key}"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = each.value.task_def
  desired_count                      = 1
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.services[each.value.tg_key].arn
    container_name   = local.svc_container_names[each.key]
    container_port   = 8080
  }

  tags = {
    Name    = "${local.prefix}-${each.key}"
    Project = "anycompany-users"
    Env     = var.env
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.http]
}

# ── App Auto Scaling ──────────────────────────────────────────────────────────

resource "aws_appautoscaling_target" "services" {
  for_each = local.ecs_service_defs

  max_capacity       = 5
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.main.name}/${local.prefix}-${each.key}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  depends_on = [aws_ecs_service.services]
}

resource "aws_appautoscaling_policy" "cpu" {
  for_each = local.ecs_service_defs

  name               = "${local.prefix}-${each.key}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.services[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.services[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.services[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60.0
    scale_in_cooldown  = 60
    scale_out_cooldown = 30
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_names" {
  description = "ECS service names"
  value       = { for k, s in aws_ecs_service.services : k => s.name }
}
