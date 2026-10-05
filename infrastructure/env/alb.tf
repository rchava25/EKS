# ── Security Groups ───────────────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name   = "${local.prefix}-alb-sg"
  vpc_id = local.vpc_id

  tags = {
    Name    = "${local.prefix}-alb-sg"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_security_group_rule" "alb_ingress_vpc_link" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.alb.id
  source_security_group_id = aws_security_group.vpc_link.id
}

resource "aws_security_group_rule" "alb_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

# Shared security group for all ECS tasks — ALB can reach port 8080.
resource "aws_security_group" "ecs_tasks" {
  name   = "${local.prefix}-ecs-tasks-sg"
  vpc_id = local.vpc_id

  tags = {
    Name    = "${local.prefix}-ecs-tasks-sg"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_security_group_rule" "ecs_ingress_from_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_tasks.id
  source_security_group_id = aws_security_group.alb.id
  description              = "ALB to ECS tasks on port 8080"
}

resource "aws_security_group_rule" "ecs_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs_tasks.id
}

# ── ALB ───────────────────────────────────────────────────────────────────────

resource "aws_lb" "alb" {
  name               = "${local.prefix}-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.private_subnet_ids

  tags = {
    Name    = "${local.prefix}-alb"
    Project = "anycompany-users"
    Env     = var.env
  }
}

# ── Target Groups (one per service) ──────────────────────────────────────────

locals {
  tg_services = {
    login    = { prefix = "login",    path = "/health" }
    users    = { prefix = "users",    path = "/health" }
    browse   = { prefix = "browse",   path = "/health" }
    search   = { prefix = "search",   path = "/health" }
    payment  = { prefix = "payment",  path = "/health" }
    shipping = { prefix = "shipping", path = "/health" }
  }
}

resource "aws_lb_target_group" "services" {
  for_each = local.tg_services

  name        = substr("${local.prefix}-${each.key}-tg", 0, 32)
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    path     = each.value.path
    protocol = "HTTP"
    port     = "8080"
    matcher  = "200"
  }

  tags = {
    Name    = "${local.prefix}-${each.key}-tg"
    Project = "anycompany-users"
    Env     = var.env
  }
}

# ── Listener + path-based rules ───────────────────────────────────────────────

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "{\"message\":\"Not Found\"}"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "auth" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services["login"].arn
  }
  condition {
    path_pattern {
      values = ["/auth", "/auth/*"]
    }
  }
}

resource "aws_lb_listener_rule" "users" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services["users"].arn
  }
  condition {
    path_pattern {
      values = ["/users", "/users/*"]
    }
  }
}

resource "aws_lb_listener_rule" "products" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 30
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services["browse"].arn
  }
  condition {
    path_pattern {
      values = ["/products", "/products/*"]
    }
  }
}

resource "aws_lb_listener_rule" "search" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 40
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services["search"].arn
  }
  condition {
    path_pattern {
      values = ["/search", "/search/*"]
    }
  }
}

resource "aws_lb_listener_rule" "orders" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 50
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services["payment"].arn
  }
  condition {
    path_pattern {
      values = ["/orders", "/orders/*"]
    }
  }
}

resource "aws_lb_listener_rule" "shipping" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 60
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services["shipping"].arn
  }
  condition {
    path_pattern {
      values = ["/shipping", "/shipping/*"]
    }
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "alb_arn"      { value = aws_lb.alb.arn }
output "alb_dns_name" { value = aws_lb.alb.dns_name }

output "target_group_arns" {
  description = "Target group ARNs keyed by service"
  value       = { for k, tg in aws_lb_target_group.services : k => tg.arn }
}
