resource "aws_security_group" "alb" {
  name   = "${local.prefix}-alb-sg"
  vpc_id = local.vpc_id

  tags = {
    Name    = "${local.prefix}-alb-sg"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_security_group_rule" "alb_ingress_from_vpc_link" {
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

resource "aws_lb_target_group" "login" {
  name        = substr("${local.prefix}-login-tg", 0, 32)
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    path     = "/health"
    protocol = "HTTP"
    port     = "8080"
  }

  tags = {
    Name    = "${local.prefix}-login-tg"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_lb_target_group" "users" {
  name        = substr("${local.prefix}-users-tg", 0, 32)
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    path     = "/health"
    protocol = "HTTP"
    port     = "8080"
  }

  tags = {
    Name    = "${local.prefix}-users-tg"
    Project = "anycompany-users"
    Env     = var.env
  }
}

# Single listener — path-based rules replace the NLB port-per-service approach
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
    target_group_arn = aws_lb_target_group.login.arn
  }

  condition {
    path_pattern {
      values = ["/auth/*"]
    }
  }
}

resource "aws_lb_listener_rule" "users" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.users.arn
  }

  condition {
    path_pattern {
      values = ["/users", "/users/*"]
    }
  }
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.alb.arn
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.alb.dns_name
}

output "login_tg_arn" {
  description = "Login service target group ARN"
  value       = aws_lb_target_group.login.arn
}

output "users_tg_arn" {
  description = "Users service target group ARN"
  value       = aws_lb_target_group.users.arn
}
