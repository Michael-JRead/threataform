# layer6-modules/module-opensearch/main.tf
# Layer 6 — Product Module: module-opensearch (OpenSearch Service domain)
# Detection signals: module-opensearch, opensearch, elasticsearch, search, es, aoss

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "enterprise-terraform-state-production"
    key            = "modules/module-opensearch/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock-production"
    kms_key_id     = "alias/enterprise-tfstate-key"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      "enterprise-app-id" = var.app_id
      "environment"       = var.environment
      "managed-by"        = "terraform"
      "cost-center"       = var.cost_center
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── KMS key for OpenSearch ────────────────────────────────────────────────────

resource "aws_kms_key" "opensearch" {
  description             = "KMS CMK for module-opensearch domain encryption — ${var.domain_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM Permissions"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow OpenSearch Service"
        Effect = "Allow"
        Principal = { Service = "es.amazonaws.com" }
        Action = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey", "kms:CreateGrant"]
        Resource = "*"
      }
    ]
  })

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-opensearch"
    "search"            = "opensearch"
  }
}

resource "aws_kms_alias" "opensearch" {
  name          = "alias/enterprise-opensearch-${var.domain_name}"
  target_key_id = aws_kms_key.opensearch.key_id
}

# ── IAM Service Role for OpenSearch ───────────────────────────────────────────

resource "aws_iam_service_linked_role" "opensearch" {
  count            = var.create_service_linked_role ? 1 : 0
  aws_service_name = "es.amazonaws.com"
  description      = "module-opensearch: Service linked role for Amazon OpenSearch Service"
}

# ── OpenSearch Domain ─────────────────────────────────────────────────────────

resource "aws_opensearch_domain" "enterprise" {
  domain_name    = var.domain_name
  engine_version = "OpenSearch_2.11"

  # Cluster configuration
  cluster_config {
    instance_type            = var.data_node_type
    instance_count           = var.data_node_count
    zone_awareness_enabled   = true
    dedicated_master_enabled = var.data_node_count >= 3 ? true : false
    dedicated_master_type    = var.master_node_type
    dedicated_master_count   = var.data_node_count >= 3 ? 3 : 0
    warm_enabled             = var.warm_enabled
    warm_type                = var.warm_enabled ? "ultrawarm1.medium.search" : null
    warm_count               = var.warm_enabled ? 2 : null

    zone_awareness_config {
      availability_zone_count = 3
    }
  }

  # Storage
  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = var.ebs_volume_size_gb
    throughput  = 250
    iops        = 3000
  }

  # Encryption
  encrypt_at_rest {
    enabled    = true
    kms_key_id = aws_kms_key.opensearch.arn
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https                   = true
    tls_security_policy             = "Policy-Min-TLS-1-2-PFS-2023-10"
    custom_endpoint_enabled         = var.custom_endpoint != "" ? true : false
    custom_endpoint                 = var.custom_endpoint != "" ? var.custom_endpoint : null
    custom_endpoint_certificate_arn = var.custom_endpoint_cert_arn != "" ? var.custom_endpoint_cert_arn : null
  }

  # Fine-grained access control — HIPAA/PCI multi-tenant access control
  advanced_security_options {
    enabled                        = true
    anonymous_auth_enabled         = false
    internal_user_database_enabled = false  # Use IAM/SAML only

    master_user_options {
      master_user_arn = var.master_user_arn
    }
  }

  # VPC deployment — no public access
  vpc_options {
    subnet_ids         = slice(var.opensearch_subnet_ids, 0, min(3, length(var.opensearch_subnet_ids)))
    security_group_ids = [var.opensearch_security_group_id]
  }

  # Logging
  log_publishing_options {
    cloudwatch_log_group_arn = "${aws_cloudwatch_log_group.index_slow.arn}:*"
    log_type                 = "INDEX_SLOW_LOGS"
    enabled                  = true
  }

  log_publishing_options {
    cloudwatch_log_group_arn = "${aws_cloudwatch_log_group.search_slow.arn}:*"
    log_type                 = "SEARCH_SLOW_LOGS"
    enabled                  = true
  }

  log_publishing_options {
    cloudwatch_log_group_arn = "${aws_cloudwatch_log_group.application.arn}:*"
    log_type                 = "ES_APPLICATION_LOGS"
    enabled                  = true
  }

  log_publishing_options {
    cloudwatch_log_group_arn = "${aws_cloudwatch_log_group.audit.arn}:*"
    log_type                 = "AUDIT_LOGS"
    enabled                  = true
  }

  # Snapshot
  snapshot_options {
    automated_snapshot_start_hour = 3
  }

  # Advanced options
  advanced_options = {
    "rest.action.multi.allow_explicit_index"      = "true"
    "indices.query.bool.max_clause_count"          = "1024"
    "indices.fielddata.cache.size"                 = "20"
    "override_main_response_version"               = "false"
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = var.allowed_principal_arns
        }
        Action   = "es:*"
        Resource = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.domain_name}/*"
      }
    ]
  })

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-opensearch"
    "opensearch"        = "true"
    "elasticsearch"     = "migrated-to-opensearch"
    "search"            = "true"
    "es"                = "domain"
    "aoss"              = "false"
    "data-classification" = var.data_classification
  }
}

# ── CloudWatch Log Groups ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "index_slow" {
  name              = "/enterprise/opensearch/${var.domain_name}/index-slow"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.opensearch.arn
  tags = { "enterprise-app-id" = var.app_id, "managed-by" = "terraform", "module" = "module-opensearch" }
}

resource "aws_cloudwatch_log_group" "search_slow" {
  name              = "/enterprise/opensearch/${var.domain_name}/search-slow"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.opensearch.arn
  tags = { "enterprise-app-id" = var.app_id, "managed-by" = "terraform", "module" = "module-opensearch" }
}

resource "aws_cloudwatch_log_group" "application" {
  name              = "/enterprise/opensearch/${var.domain_name}/application"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.opensearch.arn
  tags = { "enterprise-app-id" = var.app_id, "managed-by" = "terraform", "module" = "module-opensearch" }
}

resource "aws_cloudwatch_log_group" "audit" {
  name              = "/enterprise/opensearch/${var.domain_name}/audit"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.opensearch.arn
  tags = { "enterprise-app-id" = var.app_id, "managed-by" = "terraform", "module" = "module-opensearch", "data-classification" = "confidential" }
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "red_cluster" {
  alarm_name          = "enterprise-opensearch-${var.domain_name}-red-cluster"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ClusterStatus.red"
  namespace           = "AWS/ES"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "module-opensearch: OpenSearch cluster status RED — data availability impact"
  alarm_actions       = [var.sns_alert_arn]

  dimensions = { DomainName = aws_opensearch_domain.enterprise.domain_name, ClientId = data.aws_caller_identity.current.account_id }
}

resource "aws_cloudwatch_metric_alarm" "storage_low" {
  alarm_name          = "enterprise-opensearch-${var.domain_name}-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/ES"
  period              = 300
  statistic           = "Minimum"
  threshold           = 20480  # 20 GB in MB
  alarm_description   = "module-opensearch: OpenSearch free storage < 20GB"
  alarm_actions       = [var.sns_alert_arn]

  dimensions = { DomainName = aws_opensearch_domain.enterprise.domain_name, ClientId = data.aws_caller_identity.current.account_id }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "domain_endpoint" {
  value     = aws_opensearch_domain.enterprise.endpoint
  sensitive = true
}

output "domain_arn"      { value = aws_opensearch_domain.enterprise.arn }
output "domain_id"       { value = aws_opensearch_domain.enterprise.domain_id }
output "kibana_endpoint" { value = aws_opensearch_domain.enterprise.kibana_endpoint; sensitive = true }
output "kms_key_arn"     { value = aws_kms_key.opensearch.arn }

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region"                  { type = string; default = "us-east-1" }
variable "environment"                 { type = string; default = "production" }
variable "app_id"                      { type = string }
variable "cost_center"                 { type = string; default = "CC-DATA-006" }
variable "domain_name"                 { type = string }
variable "data_node_type"              { type = string; default = "m6g.large.search" }
variable "data_node_count"             { type = number; default = 3 }
variable "master_node_type"            { type = string; default = "m6g.large.search" }
variable "ebs_volume_size_gb"          { type = number; default = 100 }
variable "warm_enabled"                { type = bool;   default = false }
variable "create_service_linked_role"  { type = bool;   default = false }
variable "custom_endpoint"             { type = string; default = "" }
variable "custom_endpoint_cert_arn"    { type = string; default = "" }
variable "master_user_arn"             { type = string }
variable "allowed_principal_arns"      { type = list(string) }
variable "opensearch_subnet_ids"       { type = list(string) }
variable "opensearch_security_group_id" { type = string }
variable "sns_alert_arn"               { type = string }
variable "data_classification"         { type = string; default = "internal" }
