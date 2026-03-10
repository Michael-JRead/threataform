# layer6-modules/module-msk-connect/main.tf
# Layer 6 — Product Module: module-msk-connect (MSK Kafka cluster + MSK Connect)
# Detection signals: module-msk-connect, msk, kafka, messaging, mskconnect, msk_connect

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "enterprise-terraform-state-production"
    key            = "modules/module-msk-connect/terraform.tfstate"
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

# ── KMS key for MSK encryption ────────────────────────────────────────────────

resource "aws_kms_key" "msk" {
  description             = "KMS CMK for module-msk-connect Kafka encryption — ${var.cluster_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-msk-connect"
    "kafka"             = "msk"
    "messaging"         = "true"
  }
}

resource "aws_kms_alias" "msk" {
  name          = "alias/enterprise-msk-${var.cluster_name}"
  target_key_id = aws_kms_key.msk.key_id
}

# ── MSK Cluster Configuration ─────────────────────────────────────────────────

resource "aws_msk_configuration" "enterprise" {
  name              = "enterprise-kafka-config-${var.cluster_name}"
  description       = "module-msk-connect: Enterprise Kafka configuration — security hardened"
  kafka_versions    = ["3.5.1"]

  server_properties = <<-EOF
    # Replication and reliability
    default.replication.factor=3
    min.insync.replicas=2
    num.partitions=12
    num.io.threads=8
    num.network.threads=5

    # Security
    allow.everyone.if.no.acl.found=false
    authorizer.class.name=kafka.security.authorizer.AclAuthorizer
    ssl.client.auth=required

    # Log retention
    log.retention.hours=168
    log.retention.bytes=1073741824
    log.segment.bytes=1073741824
    log.cleanup.policy=delete

    # Performance
    socket.send.buffer.bytes=102400
    socket.receive.buffer.bytes=102400
    socket.request.max.bytes=104857600
    message.max.bytes=5242880
    replica.fetch.max.bytes=5242880

    # Monitoring
    kafka.metrics.reporters=com.amazonaws.services.kafka.model.BrokerLogs
    auto.leader.rebalance.enable=true
    leader.imbalance.check.interval.seconds=300

    # Topic management
    auto.create.topics.enable=false
    delete.topic.enable=true
  EOF
}

# ── MSK Cluster ───────────────────────────────────────────────────────────────

resource "aws_msk_cluster" "enterprise" {
  cluster_name           = var.cluster_name
  kafka_version          = "3.5.1"
  number_of_broker_nodes = var.broker_count
  configuration_info {
    arn      = aws_msk_configuration.enterprise.arn
    revision = aws_msk_configuration.enterprise.latest_revision
  }

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = var.broker_subnet_ids
    security_groups = [var.msk_security_group_id]

    storage_info {
      ebs_storage_info {
        provisioned_throughput {
          enabled           = true
          volume_throughput = 250
        }
        volume_size = var.broker_ebs_size_gb
      }
    }
  }

  # Security: SASL/SCRAM + TLS
  client_authentication {
    sasl {
      scram = true
      iam   = true
    }
    tls {
      certificate_authority_arns = []
    }
    unauthenticated = false
  }

  # Encryption
  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.msk.arn
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  # Logging
  broker_logs {
    cloudwatch_logs {
      enabled   = true
      log_group = aws_cloudwatch_log_group.msk_broker.name
    }
    s3 {
      enabled = true
      bucket  = var.msk_logs_bucket
      prefix  = "msk/${var.cluster_name}/"
    }
  }

  # Monitoring
  enhanced_monitoring = "PER_TOPIC_PER_BROKER"

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-msk-connect"
    "kafka"             = "true"
    "messaging"         = "true"
    "msk"               = "cluster"
    "queue"             = "kafka"
    "topic"             = "enterprise-streaming"
  }
}

# ── MSK Connect ───────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "msk_broker" {
  name              = "/enterprise/msk/${var.cluster_name}/broker-logs"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.msk.arn

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-msk-connect"
  }
}

resource "aws_cloudwatch_log_group" "msk_connect" {
  name              = "/enterprise/msk/${var.cluster_name}/connect-logs"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.msk.arn

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-msk-connect"
  }
}

# MSK Connect Worker Configuration
resource "aws_mskconnect_worker_configuration" "s3_sink" {
  name                    = "enterprise-msk-connect-s3-${var.cluster_name}"
  properties_file_content = <<-EOF
    # S3 Sink Connector configuration for MSK Connect (mskconnect)
    connector.class=io.confluent.connect.s3.S3SinkConnector
    tasks.max=4
    topics.regex=enterprise.*
    s3.region=${var.aws_region}
    s3.bucket.name=${var.msk_logs_bucket}
    s3.part.size=67108864
    flush.size=10000
    storage.class=io.confluent.connect.s3.storage.S3Storage
    format.class=io.confluent.connect.s3.format.json.JsonFormat
    schema.compatibility=NONE
    timestamp.extractor=RecordField
    timestamp.field=timestamp
    rotate.schedule.interval.ms=3600000
    locale=en_US
    timezone=UTC
    value.converter=org.apache.kafka.connect.json.JsonConverter
    key.converter=org.apache.kafka.connect.storage.StringConverter
  EOF
}

# MSK Connect Connector — S3 sink for data archiving
resource "aws_mskconnect_connector" "s3_sink" {
  name = "enterprise-msk-s3-sink-${var.cluster_name}"
  kafkaconnect_version = "2.7.1"

  capacity {
    autoscaling {
      mcu_count        = 1
      min_worker_count = 1
      max_worker_count = 4
      scale_in_policy {
        cpu_utilization_percentage = 20
      }
      scale_out_policy {
        cpu_utilization_percentage = 80
      }
    }
  }

  connector_configuration = {
    "connector.class"  = "io.confluent.connect.s3.S3SinkConnector"
    "tasks.max"        = "4"
    "topics"           = "enterprise.events,enterprise.audit,enterprise.transactions"
    "s3.region"        = var.aws_region
    "s3.bucket.name"   = var.msk_logs_bucket
    "flush.size"       = "10000"
    "storage.class"    = "io.confluent.connect.s3.storage.S3Storage"
    "format.class"     = "io.confluent.connect.s3.format.json.JsonFormat"
    "schema.compatibility" = "NONE"
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = aws_msk_cluster.enterprise.bootstrap_brokers_sasl_iam
      vpc {
        security_groups = [var.msk_security_group_id]
        subnets         = var.broker_subnet_ids
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "IAM"
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "TLS"
  }

  plugin {
    custom_plugin {
      arn      = var.s3_sink_plugin_arn
      revision = 1
    }
  }

  service_execution_role_arn = aws_iam_role.msk_connect.arn

  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk_connect.name
      }
      s3 {
        enabled = true
        bucket  = var.msk_logs_bucket
        prefix  = "msk-connect/${var.cluster_name}/"
      }
    }
  }

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-msk-connect"
    "mskconnect"        = "true"
    "msk_connect"       = "s3-sink"
    "kafka"             = "connector"
    "messaging"         = "streaming"
    "topic"             = "enterprise-events"
    "queue"             = "enterprise-streaming"
  }
}

# IAM role for MSK Connect
resource "aws_iam_role" "msk_connect" {
  name                 = "enterprise-msk-connect-${var.cluster_name}"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "kafkaconnect.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-msk-connect"
  }
}

resource "aws_iam_role_policy" "msk_connect" {
  name = "enterprise-msk-connect-policy"
  role = aws_iam_role.msk_connect.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect", "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:ReadData", "kafka-cluster:WriteData",
          "kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic",
        ]
        Resource = [
          aws_msk_cluster.enterprise.arn,
          "${aws_msk_cluster.enterprise.arn}/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = ["arn:aws:s3:::${var.msk_logs_bucket}", "arn:aws:s3:::${var.msk_logs_bucket}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.msk_connect.arn}:*"
      }
    ]
  })
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "msk_offline_partitions" {
  alarm_name          = "enterprise-msk-${var.cluster_name}-offline-partitions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "OfflinePartitionsCount"
  namespace           = "AWS/Kafka"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "module-msk-connect: Kafka has offline partitions — data loss risk"
  alarm_actions       = [var.sns_alert_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    "Cluster Name" = aws_msk_cluster.enterprise.cluster_name
  }
}

resource "aws_cloudwatch_metric_alarm" "msk_consumer_lag" {
  alarm_name          = "enterprise-msk-${var.cluster_name}-consumer-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "EstimatedMaxTimeLag"
  namespace           = "AWS/Kafka"
  period              = 300
  statistic           = "Maximum"
  threshold           = 60000  # 60 seconds lag
  alarm_description   = "module-msk-connect: Kafka consumer lag > 60s"
  alarm_actions       = [var.sns_alert_arn]

  dimensions = {
    "Cluster Name" = aws_msk_cluster.enterprise.cluster_name
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "kafka_bootstrap_brokers_sasl_iam"   { value = aws_msk_cluster.enterprise.bootstrap_brokers_sasl_iam;  sensitive = true }
output "kafka_bootstrap_brokers_tls"        { value = aws_msk_cluster.enterprise.bootstrap_brokers_tls;       sensitive = true }
output "cluster_arn"                        { value = aws_msk_cluster.enterprise.arn }
output "cluster_name"                       { value = aws_msk_cluster.enterprise.cluster_name }
output "zookeeper_connect_string"           { value = aws_msk_cluster.enterprise.zookeeper_connect_string; sensitive = true }
output "kms_key_arn"                        { value = aws_kms_key.msk.arn }

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region"             { type = string; default = "us-east-1" }
variable "environment"            { type = string; default = "production" }
variable "app_id"                 { type = string }
variable "cost_center"            { type = string; default = "CC-DATA-006" }
variable "cluster_name"           { type = string }
variable "broker_count"           { type = number; default = 3 }
variable "broker_instance_type"   { type = string; default = "kafka.m5.large" }
variable "broker_ebs_size_gb"     { type = number; default = 1000 }
variable "broker_subnet_ids"      { type = list(string) }
variable "msk_security_group_id"  { type = string }
variable "msk_logs_bucket"        { type = string }
variable "s3_sink_plugin_arn"     { type = string; default = "" }
variable "sns_alert_arn"          { type = string }
variable "permissions_boundary_arn" { type = string }
