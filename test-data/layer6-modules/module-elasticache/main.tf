# layer6-modules/module-elasticache/main.tf
# Layer 6 — Product Module: module-elasticache (Redis replication group)
# Detection signals: module-elasticache, elasticache, redis, cache, memcached

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "enterprise-terraform-state-production"
    key            = "modules/module-elasticache/terraform.tfstate"
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

# ── KMS key for ElastiCache encryption ───────────────────────────────────────

resource "aws_kms_key" "elasticache" {
  description             = "KMS CMK for module-elasticache Redis encryption — ${var.replication_group_id}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-elasticache"
  }
}

resource "aws_kms_alias" "elasticache" {
  name          = "alias/enterprise-elasticache-${var.replication_group_id}"
  target_key_id = aws_kms_key.elasticache.key_id
}

# ── ElastiCache Subnet Group ──────────────────────────────────────────────────

resource "aws_elasticache_subnet_group" "redis" {
  name        = "enterprise-cache-subnet-group-${var.replication_group_id}"
  description = "module-elasticache: Subnet group for Redis replication group ${var.replication_group_id}"
  subnet_ids  = var.cache_subnet_ids

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-elasticache"
  }
}

# ── Redis Parameter Group ─────────────────────────────────────────────────────

resource "aws_elasticache_parameter_group" "redis7" {
  name   = "enterprise-redis7-${var.replication_group_id}"
  family = "redis7"
  description = "module-elasticache: Enterprise Redis 7 parameters — security hardened"

  # Memory management
  parameter {
    name  = "maxmemory-policy"
    value = var.maxmemory_policy
  }

  # Security: disable dangerous commands
  parameter {
    name  = "rename-commands"
    value = "CONFIG BLOCKED FLUSHALL BLOCKED FLUSHDB BLOCKED DEBUG BLOCKED KEYS BLOCKED MONITOR BLOCKED"
  }

  # Slow query logging
  parameter {
    name  = "slowlog-log-slower-than"
    value = "10000"  # 10ms
  }

  parameter {
    name  = "slowlog-max-len"
    value = "128"
  }

  # Active defragmentation
  parameter {
    name  = "activedefrag"
    value = "yes"
  }

  # Latency monitoring
  parameter {
    name  = "latency-monitor-threshold"
    value = "50"  # 50ms
  }

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-elasticache"
  }
}

# ── Redis Replication Group (HA + encryption) ─────────────────────────────────

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = var.replication_group_id
  description          = "module-elasticache: Enterprise Redis for ${var.app_id} — ${var.environment}"

  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_nodes
  parameter_group_name = aws_elasticache_parameter_group.redis7.name
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [var.cache_security_group_id]
  port                 = 6379

  engine_version       = "7.1"

  # Security: encryption
  at_rest_encryption_enabled = true
  kms_key_id                 = aws_kms_key.elasticache.arn
  transit_encryption_enabled = true
  auth_token                 = var.redis_auth_token
  auth_token_update_strategy = "ROTATE"

  # HA configuration
  automatic_failover_enabled = var.num_cache_nodes > 1 ? true : false
  multi_az_enabled           = var.num_cache_nodes > 1 ? true : false

  # Maintenance
  maintenance_window        = "sun:05:00-sun:06:00"
  snapshot_window           = "03:00-04:00"
  snapshot_retention_limit  = 7
  final_snapshot_identifier = "${var.replication_group_id}-final"

  # Logging
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_engine_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-elasticache"
    "cache"             = "redis"
    "memcached"         = "false"
    "data-classification" = "internal"
  }
}

# ── CloudWatch Log Groups ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "redis_slow_log" {
  name              = "/enterprise/elasticache/${var.replication_group_id}/slow-log"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.elasticache.arn

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-elasticache"
  }
}

resource "aws_cloudwatch_log_group" "redis_engine_log" {
  name              = "/enterprise/elasticache/${var.replication_group_id}/engine-log"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.elasticache.arn

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-elasticache"
  }
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  alarm_name          = "enterprise-elasticache-${var.replication_group_id}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "EngineCPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "module-elasticache: Redis CPU > 70% for ${var.replication_group_id}"
  alarm_actions       = [var.sns_alert_arn]

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.redis.id
  }

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-elasticache"
  }
}

resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  alarm_name          = "enterprise-elasticache-${var.replication_group_id}-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "module-elasticache: Redis memory > 80% for ${var.replication_group_id}"
  alarm_actions       = [var.sns_alert_arn]

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.redis.id
  }
}

resource "aws_cloudwatch_metric_alarm" "redis_evictions" {
  alarm_name          = "enterprise-elasticache-${var.replication_group_id}-evictions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Evictions"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Sum"
  threshold           = 1000
  alarm_description   = "module-elasticache: Redis evictions > 1000 — cache memory pressure"
  alarm_actions       = [var.sns_alert_arn]

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.redis.id
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "primary_endpoint" {
  value     = aws_elasticache_replication_group.redis.primary_endpoint_address
  sensitive = true
}

output "reader_endpoint" {
  value     = aws_elasticache_replication_group.redis.reader_endpoint_address
  sensitive = true
}

output "port" {
  value = aws_elasticache_replication_group.redis.port
}

output "kms_key_arn" {
  value = aws_kms_key.elasticache.arn
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region"              { type = string; default = "us-east-1" }
variable "environment"             { type = string; default = "production" }
variable "app_id"                  { type = string }
variable "cost_center"             { type = string; default = "CC-DATA-006" }
variable "replication_group_id"    { type = string }
variable "node_type"               { type = string; default = "cache.r6g.large" }
variable "num_cache_nodes"         { type = number; default = 2 }
variable "maxmemory_policy"        { type = string; default = "allkeys-lru" }
variable "redis_auth_token"        { type = string; sensitive = true }
variable "cache_subnet_ids"        { type = list(string) }
variable "cache_security_group_id" { type = string }
variable "sns_alert_arn"           { type = string }
