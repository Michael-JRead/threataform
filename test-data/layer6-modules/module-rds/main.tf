# layer6-modules/module-rds/main.tf
# Layer 6 — Product Module: module-rds (RDS Aurora PostgreSQL cluster)
# Detection signals: module-rds, rds, database, aurora, postgresql

terraform {
  required_providers {
    aws   = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
  backend "s3" {
    bucket         = "enterprise-terraform-state-production"
    key            = "modules/module-rds/terraform.tfstate"
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

# ── KMS key for RDS encryption ────────────────────────────────────────────────

resource "aws_kms_key" "rds" {
  description             = "KMS CMK for module-rds Aurora cluster encryption — ${var.cluster_identifier}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  multi_region            = false

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow RDS Service"
        Effect = "Allow"
        Principal = { Service = "rds.amazonaws.com" }
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
    "module"            = "module-rds"
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/enterprise-rds-${var.cluster_identifier}"
  target_key_id = aws_kms_key.rds.key_id
}

# ── Random suffix for globally unique identifiers ─────────────────────────────

resource "random_id" "db_suffix" {
  byte_length = 4
}

# ── RDS Cluster Parameter Groups ──────────────────────────────────────────────

resource "aws_rds_cluster_parameter_group" "aurora_pg15" {
  name        = "enterprise-aurora-pg15-${var.cluster_identifier}"
  family      = "aurora-postgresql15"
  description = "module-rds: Enterprise Aurora PostgreSQL 15 parameter group — security hardened"

  # Security hardening parameters
  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_duration"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"  # Log queries > 1s
  }

  parameter {
    name  = "log_statement"
    value = "ddl"  # Log all DDL statements (SOX audit)
  }

  parameter {
    name  = "log_lock_waits"
    value = "1"
  }

  parameter {
    name         = "ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements,pgaudit"
  }

  parameter {
    name  = "pgaudit.log"
    value = "DDL,WRITE,ROLE"  # HIPAA/SOX audit logging
  }

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "password_encryption"
    value = "scram-sha-256"
  }

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-rds"
  }
}

resource "aws_db_parameter_group" "aurora_pg15_instance" {
  name   = "enterprise-aurora-pg15-instance-${var.cluster_identifier}"
  family = "aurora-postgresql15"
  description = "module-rds: Instance-level parameters for Aurora PG15"

  parameter {
    name  = "log_min_error_statement"
    value = "error"
  }

  parameter {
    name  = "log_temp_files"
    value = "0"
  }

  parameter {
    name  = "track_activities"
    value = "1"
  }

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-rds"
  }
}

# ── DB Subnet Group ───────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "aurora" {
  name        = "enterprise-db-subnet-group-${var.cluster_identifier}"
  description = "module-rds: Subnet group for Aurora cluster ${var.cluster_identifier}"
  subnet_ids  = var.db_subnet_ids

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-rds"
  }
}

# ── Aurora PostgreSQL Cluster ─────────────────────────────────────────────────

resource "aws_rds_cluster" "aurora_primary" {
  cluster_identifier              = var.cluster_identifier
  engine                         = "aurora-postgresql"
  engine_version                 = "15.4"
  engine_mode                    = "provisioned"
  database_name                  = var.database_name
  master_username                = var.master_username
  manage_master_user_password    = true  # Secrets Manager rotation (no plaintext password)
  master_user_secret_kms_key_id  = aws_kms_key.rds.arn

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora_pg15.name
  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  vpc_security_group_ids          = [var.db_security_group_id]

  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  deletion_protection         = true
  skip_final_snapshot         = false
  final_snapshot_identifier   = "${var.cluster_identifier}-final-${random_id.db_suffix.hex}"
  copy_tags_to_snapshot       = true

  backup_retention_period = var.backup_retention_days
  preferred_backup_window = "02:00-03:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  iam_database_authentication_enabled = true  # IAM auth (no password for apps)

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.rds.arn
  performance_insights_retention_period = 731  # 2 years

  serverlessv2_scaling_configuration {
    max_capacity = var.max_acu
    min_capacity = var.min_acu
  }

  tags = {
    "enterprise-app-id"   = var.app_id
    "environment"         = var.environment
    "managed-by"          = "terraform"
    "cost-center"         = var.cost_center
    "module"              = "module-rds"
    "postgresql"          = "aurora"
    "database"            = "primary"
    "data-classification" = var.data_classification
  }
}

# ── Cluster Instances ─────────────────────────────────────────────────────────

resource "aws_rds_cluster_instance" "writer" {
  identifier             = "${var.cluster_identifier}-writer"
  cluster_identifier     = aws_rds_cluster.aurora_primary.id
  instance_class         = "db.serverless"
  engine                 = aws_rds_cluster.aurora_primary.engine
  engine_version         = aws_rds_cluster.aurora_primary.engine_version
  db_parameter_group_name = aws_db_parameter_group.aurora_pg15_instance.name

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.rds.arn
  performance_insights_retention_period = 731

  publicly_accessible    = false
  auto_minor_version_upgrade = true

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-rds"
    "role"              = "writer"
  }
}

resource "aws_rds_cluster_instance" "reader" {
  count                  = var.reader_count
  identifier             = "${var.cluster_identifier}-reader-${count.index + 1}"
  cluster_identifier     = aws_rds_cluster.aurora_primary.id
  instance_class         = "db.serverless"
  engine                 = aws_rds_cluster.aurora_primary.engine
  engine_version         = aws_rds_cluster.aurora_primary.engine_version
  db_parameter_group_name = aws_db_parameter_group.aurora_pg15_instance.name

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.rds.arn

  publicly_accessible        = false
  auto_minor_version_upgrade = true

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-rds"
    "role"              = "reader-${count.index + 1}"
  }
}

# ── CloudWatch Monitoring ─────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "db_cpu_high" {
  alarm_name          = "enterprise-rds-${var.cluster_identifier}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "module-rds: Aurora CPU > 80% for ${var.cluster_identifier}"
  alarm_actions       = [var.sns_alert_arn]
  ok_actions          = [var.sns_alert_arn]

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora_primary.id
  }

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-rds"
  }
}

resource "aws_cloudwatch_metric_alarm" "db_connections_high" {
  alarm_name          = "enterprise-rds-${var.cluster_identifier}-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Sum"
  threshold           = 900
  alarm_description   = "module-rds: Aurora connection count > 900 (approaching max_connections)"
  alarm_actions       = [var.sns_alert_arn]

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora_primary.id
  }
}

resource "aws_cloudwatch_metric_alarm" "db_freeable_memory" {
  alarm_name          = "enterprise-rds-${var.cluster_identifier}-low-memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 536870912  # 512 MB in bytes
  alarm_description   = "module-rds: Aurora freeable memory < 512MB"
  alarm_actions       = [var.sns_alert_arn]

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora_primary.id
  }
}

# ── Secrets Manager for connection string ─────────────────────────────────────

resource "aws_secretsmanager_secret" "db_connection" {
  name        = "enterprise/${var.app_id}/${var.cluster_identifier}/db-connection"
  description = "module-rds: Aurora connection details for ${var.cluster_identifier}"
  kms_key_id  = aws_kms_key.rds.arn

  recovery_window_in_days = 30

  tags = {
    "enterprise-app-id"   = var.app_id
    "environment"         = var.environment
    "managed-by"          = "terraform"
    "cost-center"         = var.cost_center
    "module"              = "module-rds"
    "data-classification" = "confidential"
  }
}

resource "aws_secretsmanager_secret_rotation" "db_connection" {
  secret_id           = aws_secretsmanager_secret.db_connection.id
  rotation_lambda_arn = var.rotation_lambda_arn

  rotation_rules {
    automatically_after_days = 30
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "cluster_endpoint" {
  description = "module-rds: Aurora cluster writer endpoint"
  value       = aws_rds_cluster.aurora_primary.endpoint
  sensitive   = true
}

output "reader_endpoint" {
  description = "module-rds: Aurora cluster reader endpoint"
  value       = aws_rds_cluster.aurora_primary.reader_endpoint
  sensitive   = true
}

output "cluster_identifier" {
  value = aws_rds_cluster.aurora_primary.cluster_identifier
}

output "cluster_resource_id" {
  value = aws_rds_cluster.aurora_primary.cluster_resource_id
}

output "kms_key_arn" {
  value = aws_kms_key.rds.arn
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db_connection.arn
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region"          { type = string; default = "us-east-1" }
variable "environment"         { type = string; default = "production" }
variable "app_id"              { type = string; description = "enterprise-app-id tag value" }
variable "cost_center"         { type = string; default = "CC-DATA-006" }
variable "cluster_identifier"  { type = string; description = "Aurora cluster identifier" }
variable "database_name"       { type = string; description = "Initial database name" }
variable "master_username"     { type = string; description = "Master username for the database"; default = "dbadmin" }
variable "backup_retention_days" { type = number; default = 30 }
variable "min_acu"             { type = number; default = 0.5; description = "Minimum Aurora Capacity Units (serverless v2)" }
variable "max_acu"             { type = number; default = 32; description = "Maximum Aurora Capacity Units" }
variable "reader_count"        { type = number; default = 1 }
variable "db_subnet_ids"       { type = list(string) }
variable "db_security_group_id" { type = string }
variable "sns_alert_arn"       { type = string }
variable "rotation_lambda_arn" { type = string; default = "" }
variable "data_classification" { type = string; default = "confidential" }
