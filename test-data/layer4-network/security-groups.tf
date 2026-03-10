# layer4-network/security-groups.tf
# Layer 4 — Network Boundary: Security Groups with micro-segmentation
# Naming pattern: enterprise-sg-{tier}-{app}

# ── WAFv2 Web ACL (PCI-06) ────────────────────────────────────────────────────

resource "aws_wafv2_web_acl" "enterprise" {
  name        = "enterprise-waf-prod"
  description = "Enterprise WAF — PCI/OWASP Top 10 protection for all internet-facing ALBs"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action { none {} }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 3

    override_action { none {} }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesAmazonIpReputationList"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 4

    override_action { none {} }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesSQLiRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitRule"
    priority = 5

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "enterprise-waf-prod"
    sampled_requests_enabled   = true
  }

  tags = {
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

# ── Application Load Balancer Security Group ──────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "enterprise-sg-alb-prod"
  description = "ALB security group — HTTPS (443) from internet, HTTP redirect (80)"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description      = "HTTPS from internet — TLS termination at ALB"
  }

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description      = "HTTP from internet — redirected to HTTPS at ALB"
  }

  egress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    cidr_blocks     = [aws_vpc.production.cidr_block]
    description     = "Forward to app tier on port 8080"
  }

  egress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    cidr_blocks     = [aws_vpc.production.cidr_block]
    description     = "Health checks and service mesh"
  }

  tags = {
    "Name"              = "enterprise-sg-alb-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
    "security-group"    = "alb"
  }
}

# ── Application Tier Security Group ───────────────────────────────────────────

resource "aws_security_group" "app" {
  name        = "enterprise-sg-app-prod"
  description = "Application tier security group — receive from ALB only, deny direct internet"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "App traffic from ALB only — micro-segmentation"
  }

  ingress {
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Health check port from ALB"
  }

  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.database.id]
    description     = "PostgreSQL to database tier"
  }

  egress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.cache.id]
    description     = "Redis to cache tier"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for AWS API calls via NAT/VPC endpoints"
  }

  egress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.production.cidr_block]
    description = "MSK Kafka plaintext (within VPC only)"
  }

  egress {
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.production.cidr_block]
    description = "MSK Kafka TLS"
  }

  tags = {
    "Name"              = "enterprise-sg-app-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
    "security-group"    = "app"
    "securitygroup"     = "app-tier"
    "secgroup"          = "true"
  }
}

# ── Database Security Group ────────────────────────────────────────────────────

resource "aws_security_group" "database" {
  name        = "enterprise-sg-database-prod"
  description = "Database tier security group — PostgreSQL from app tier only"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "PostgreSQL from app tier — network isolation enforced"
  }

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
    description     = "PostgreSQL from Lambda data processor"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.production.cidr_block]
    description = "HTTPS for VPC endpoint access"
  }

  tags = {
    "Name"              = "enterprise-sg-database-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
    "security-group"    = "database"
    "data-classification" = "confidential"
  }
}

# ── Cache Tier Security Group ─────────────────────────────────────────────────

resource "aws_security_group" "cache" {
  name        = "enterprise-sg-cache-prod"
  description = "Cache tier security group — Redis 6379 from app tier only"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "Redis from app tier only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow egress within VPC"
  }

  tags = {
    "Name"              = "enterprise-sg-cache-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
    "security-group"    = "cache"
  }
}

# ── Lambda Security Group ─────────────────────────────────────────────────────

resource "aws_security_group" "lambda" {
  name        = "enterprise-sg-lambda-prod"
  description = "Lambda function security group — no ingress, controlled egress"
  vpc_id      = aws_vpc.production.id

  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.database.id]
    description     = "PostgreSQL to database tier"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for AWS API calls and external integrations"
  }

  tags = {
    "Name"              = "enterprise-sg-lambda-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
    "security-group"    = "lambda"
  }
}

# ── MSK Kafka Security Group ──────────────────────────────────────────────────

resource "aws_security_group" "msk" {
  name        = "enterprise-sg-msk-prod"
  description = "MSK Kafka security group — Kafka ports from app tier only"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "Kafka plaintext from app tier"
  }

  ingress {
    from_port       = 9094
    to_port         = 9094
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "Kafka TLS from app tier"
  }

  ingress {
    from_port       = 2181
    to_port         = 2181
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "ZooKeeper from app tier"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.production.cidr_block]
    description = "All egress within VPC"
  }

  tags = {
    "Name"              = "enterprise-sg-msk-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
    "security-group"    = "msk"
  }
}

# ── OpenSearch Security Group ─────────────────────────────────────────────────

resource "aws_security_group" "opensearch" {
  name        = "enterprise-sg-opensearch-prod"
  description = "OpenSearch security group — HTTPS from app tier only"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "OpenSearch HTTPS from app tier"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.production.cidr_block]
    description = "Egress within VPC"
  }

  tags = {
    "Name"              = "enterprise-sg-opensearch-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
    "security-group"    = "opensearch"
  }
}

# ── EKS Security Groups ───────────────────────────────────────────────────────

resource "aws_security_group" "eks_control_plane" {
  name        = "enterprise-sg-eks-controlplane-prod"
  description = "EKS control plane security group"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
    description     = "Worker node to control plane HTTPS"
  }

  egress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
    description     = "Control plane to worker nodes"
  }

  tags = {
    "Name"              = "enterprise-sg-eks-controlplane-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
    "security-group"    = "eks-control-plane"
  }
}

resource "aws_security_group" "eks_nodes" {
  name        = "enterprise-sg-eks-nodes-prod"
  description = "EKS worker node security group — node-to-node + control plane"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
    description = "Node-to-node communication"
  }

  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_control_plane.id]
    description     = "Control plane to worker nodes"
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_control_plane.id]
    description     = "HTTPS from control plane"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all egress (required for pulling images, AWS APIs)"
  }

  tags = {
    "Name"              = "enterprise-sg-eks-nodes-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
    "security-group"    = "eks-nodes"
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "sg_alb_id"         { value = aws_security_group.alb.id }
output "sg_app_id"         { value = aws_security_group.app.id }
output "sg_database_id"    { value = aws_security_group.database.id }
output "sg_cache_id"       { value = aws_security_group.cache.id }
output "sg_lambda_id"      { value = aws_security_group.lambda.id }
output "sg_msk_id"         { value = aws_security_group.msk.id }
output "sg_opensearch_id"  { value = aws_security_group.opensearch.id }
output "sg_eks_nodes_id"   { value = aws_security_group.eks_nodes.id }
output "sg_eks_cp_id"      { value = aws_security_group.eks_control_plane.id }
output "waf_web_acl_arn"   { value = aws_wafv2_web_acl.enterprise.arn }
