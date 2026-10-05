# ── Amazon OpenSearch Service — search-service ────────────────────────────────

resource "aws_security_group" "opensearch" {
  name   = "${local.prefix}-opensearch-sg"
  vpc_id = local.vpc_id

  tags = {
    Name    = "${local.prefix}-opensearch-sg"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_security_group_rule" "opensearch_from_ecs" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.opensearch.id
  source_security_group_id = aws_security_group.ecs_tasks.id
  description              = "Search service OpenSearch HTTPS access"
}

resource "aws_security_group_rule" "opensearch_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.opensearch.id
}

resource "aws_opensearch_domain" "search" {
  domain_name    = "${local.prefix}-search"
  engine_version = "OpenSearch_2.11"

  cluster_config {
    instance_type  = "t3.small.search"
    instance_count = 1
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 20
  }

  vpc_options {
    subnet_ids         = [local.private_subnet_ids[0]]
    security_group_ids = [aws_security_group.opensearch.id]
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https = true
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.search_service.arn }
      Action    = "es:*"
      Resource  = "arn:aws:es:${var.aws_region}:*:domain/${local.prefix}-search/*"
    }]
  })

  tags = {
    Name    = "${local.prefix}-search"
    Project = "anycompany-users"
    Env     = var.env
  }
}

output "opensearch_endpoint" {
  description = "OpenSearch domain endpoint for search-service"
  value       = aws_opensearch_domain.search.endpoint
}
