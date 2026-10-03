resource "aws_lb" "nlb" {
  name               = "${local.prefix}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = local.public_subnet_ids

  tags = {
    Name    = "${local.prefix}-nlb"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_lb_target_group" "login" {
  name        = substr("${local.prefix}-login-tg", 0, 32)
  port        = 80
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    protocol = "TCP"
    port     = "80"
  }

  tags = {
    Name    = "${local.prefix}-login-tg"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_lb_target_group" "users" {
  name        = substr("${local.prefix}-users-tg", 0, 32)
  port        = 80
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    protocol = "TCP"
    port     = "80"
  }

  tags = {
    Name    = "${local.prefix}-users-tg"
    Project = "anycompany-users"
    Env     = var.env
  }
}

# Port 80 → login-service
resource "aws_lb_listener" "login" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.login.arn
  }
}

# Port 8080 → users-service (NLB has no path-based routing, so distinct ports per service)
resource "aws_lb_listener" "users" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 8080
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.users.arn
  }
}

output "nlb_arn" {
  description = "NLB ARN"
  value       = aws_lb.nlb.arn
}

output "nlb_dns_name" {
  description = "NLB DNS name"
  value       = aws_lb.nlb.dns_name
}

output "login_tg_arn" {
  description = "Login service target group ARN"
  value       = aws_lb_target_group.login.arn
}

output "users_tg_arn" {
  description = "Users service target group ARN"
  value       = aws_lb_target_group.users.arn
}
