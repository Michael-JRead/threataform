# layer6-modules/module-kendra/main.tf
# Layer 6 — Product Module: module-kendra (Amazon Kendra enterprise search)
# Detection signals: module-kendra, kendra, enterprise-search, search-service

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "enterprise-terraform-state-production"
    key            = "modules/module-kendra/terraform.tfstate"
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

# ── KMS key for Kendra ────────────────────────────────────────────────────────

resource "aws_kms_key" "kendra" {
  description             = "KMS CMK for module-kendra enterprise search index"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-kendra"
    "kendra"            = "enterprise-search"
    "search"            = "true"
  }
}

resource "aws_kms_alias" "kendra" {
  name          = "alias/enterprise-kendra-${var.index_name}"
  target_key_id = aws_kms_key.kendra.key_id
}

# ── IAM Role for Kendra ───────────────────────────────────────────────────────

resource "aws_iam_role" "kendra" {
  name                 = "enterprise-kendra-${var.index_name}"
  description          = "module-kendra: IAM role for Kendra enterprise-search index"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "kendra.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-kendra"
    "kendra"            = "enterprise-search"
  }
}

resource "aws_iam_role_policy" "kendra" {
  name = "enterprise-kendra-policy"
  role = aws_iam_role.kendra.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = ["cloudwatch:PutMetricData", "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
        Resource = "*"
        Condition = {
          StringEquals = { "cloudwatch:namespace" = "Kendra" }
        }
      },
      {
        Sid    = "S3DataSourceAccess"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = concat(
          [for b in var.s3_data_source_buckets : "arn:aws:s3:::${b}"],
          [for b in var.s3_data_source_buckets : "arn:aws:s3:::${b}/*"],
        )
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = aws_kms_key.kendra.arn
      }
    ]
  })
}

# ── Kendra Index ──────────────────────────────────────────────────────────────

resource "aws_kendra_index" "enterprise" {
  name        = var.index_name
  description = "module-kendra: Enterprise search index for ${var.app_id} — ${var.environment}"
  role_arn    = aws_iam_role.kendra.arn
  edition     = var.kendra_edition  # ENTERPRISE_EDITION or DEVELOPER_EDITION

  server_side_encryption_configuration {
    kms_key_id = aws_kms_key.kendra.arn
  }

  capacity_units {
    query_capacity_units   = var.query_capacity_units
    storage_capacity_units = var.storage_capacity_units
  }

  user_context_policy = "USER_TOKEN"

  user_token_configurations {
    jwt_token_type_configuration {
      key_location               = "URL"
      url                        = var.jwks_url
      user_name_attribute_field  = "email"
      group_attribute_field      = "groups"
    }
  }

  document_metadata_configuration_updates {
    name     = "enterprise-app-id"
    type     = "STRING_VALUE"
    relevance {
      importance = 2
    }
    search {
      displayable = true
      searchable  = true
    }
  }

  document_metadata_configuration_updates {
    name     = "department"
    type     = "STRING_VALUE"
    relevance {
      importance = 1
    }
    search {
      displayable = true
      facetable   = true
      searchable  = true
    }
  }

  document_metadata_configuration_updates {
    name     = "data-classification"
    type     = "STRING_VALUE"
    relevance {
      importance = 3
    }
    search {
      displayable = true
      facetable   = true
      searchable  = false
    }
  }

  document_metadata_configuration_updates {
    name     = "last-modified"
    type     = "DATE_VALUE"
    relevance {
      importance       = 1
      freshness        = true
      duration         = "180"
      rank_order       = "ASCENDING"
    }
    search {
      displayable = true
      sortable    = true
    }
  }

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-kendra"
    "kendra"            = "enterprise-search"
    "search"            = "true"
    "search-service"    = "kendra"
    "enterprise-search" = "true"
  }
}

# ── Kendra Data Sources ───────────────────────────────────────────────────────

resource "aws_kendra_data_source" "s3_documents" {
  count     = length(var.s3_data_source_buckets) > 0 ? 1 : 0
  index_id  = aws_kendra_index.enterprise.id
  name      = "${var.index_name}-s3-documents"
  type      = "S3"
  role_arn  = aws_iam_role.kendra.arn
  schedule  = "cron(0 3 * * ? *)"  # Daily at 3 AM

  description = "module-kendra: S3 document data source for enterprise-search index"

  configuration {
    s3_configuration {
      bucket_name = var.s3_data_source_buckets[0]

      inclusion_patterns = ["*.pdf", "*.docx", "*.txt", "*.html", "*.md"]
      exclusion_patterns = ["*.tmp", "*.log", "*.zip", "private/*"]

      documents_metadata_configuration {
        s3_prefix = "metadata/"
      }

      access_control_list_configuration {
        key_path = "s3://${var.s3_data_source_buckets[0]}/acl/access-control.json"
      }
    }
  }

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-kendra"
    "kendra"            = "data-source-s3"
  }
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "kendra_query_count" {
  alarm_name          = "enterprise-kendra-${var.index_name}-query-capacity"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "QueryCount"
  namespace           = "AWS/Kendra"
  period              = 60
  statistic           = "Sum"
  threshold           = var.query_capacity_units * 700  # 70% of capacity
  alarm_description   = "module-kendra: Kendra query count approaching capacity limit"
  alarm_actions       = [var.sns_alert_arn]

  dimensions = {
    IndexId = aws_kendra_index.enterprise.id
  }

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-kendra"
  }
}

resource "aws_cloudwatch_metric_alarm" "kendra_indexing_errors" {
  alarm_name          = "enterprise-kendra-${var.index_name}-indexing-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DocumentsFailedToIndexCount"
  namespace           = "AWS/Kendra"
  period              = 3600
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "module-kendra: Kendra document indexing failures > 10 in 1 hour"
  alarm_actions       = [var.sns_alert_arn]

  dimensions = {
    IndexId = aws_kendra_index.enterprise.id
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "kendra_index_id"   { value = aws_kendra_index.enterprise.id }
output "kendra_index_arn"  { value = aws_kendra_index.enterprise.arn }
output "kendra_role_arn"   { value = aws_iam_role.kendra.arn }
output "kms_key_arn"       { value = aws_kms_key.kendra.arn }

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region"               { type = string; default = "us-east-1" }
variable "environment"              { type = string; default = "production" }
variable "app_id"                   { type = string }
variable "cost_center"              { type = string; default = "CC-DATA-006" }
variable "index_name"               { type = string }
variable "kendra_edition"           { type = string; default = "ENTERPRISE_EDITION" }
variable "query_capacity_units"     { type = number; default = 1 }
variable "storage_capacity_units"   { type = number; default = 0 }
variable "s3_data_source_buckets"   { type = list(string); default = [] }
variable "jwks_url"                 { type = string; default = "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_xxx/.well-known/jwks.json" }
variable "sns_alert_arn"            { type = string }
variable "permissions_boundary_arn" { type = string }
