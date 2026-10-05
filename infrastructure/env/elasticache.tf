# ── ElastiCache Redis — browse-service product cache ─────────────────────────

resource "aws_security_group" "redis" {
  name   = "${local.prefix}-redis-sg"
  vpc_id = local.vpc_id

  tags = {
    Name    = "${local.prefix}-redis-sg"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_security_group_rule" "redis_from_ecs" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis.id
  source_security_group_id = aws_security_group.ecs_tasks.id
  description              = "Browse service Redis access"
}

resource "aws_security_group_rule" "redis_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.redis.id
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.prefix}-cache-subnets"
  subnet_ids = local.private_subnet_ids

  tags = {
    Name    = "${local.prefix}-cache-subnets"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_elasticache_cluster" "browse" {
  cluster_id           = "${local.prefix}-browse-cache"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.redis.id]

  tags = {
    Name    = "${local.prefix}-browse-cache"
    Project = "anycompany-users"
    Env     = var.env
  }
}

output "redis_endpoint" {
  description = "Redis endpoint for browse-service"
  value       = aws_elasticache_cluster.browse.cache_nodes[0].address
}

output "redis_port" {
  value = aws_elasticache_cluster.browse.port
}
