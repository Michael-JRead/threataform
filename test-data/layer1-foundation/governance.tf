# layer1-foundation/governance.tf
# Layer 1 — Foundation: CloudTrail, Config, GuardDuty, Security Hub, Macie, IAM Access Analyzer
# Covers: SOX-02 (CloudTrail+log validation), PCI-04/05, GDPR-04/05, HIPAA-02/06

# ── Organization-wide CloudTrail ─────────────────────────────────────────────

resource "aws_cloudtrail" "organization" {
  name                          = "enterprise-org-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  s3_key_prefix                 = "cloudtrail"
  is_multi_region_trail         = true
  is_organization_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true   # SOX-02 required
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_cloudwatch.arn
  kms_key_id                    = aws_kms_key.cloudtrail.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]
    }

    data_resource {
      type   = "AWS::Lambda::Function"
      values = ["arn:aws:lambda"]
    }
  }

  insight_selector {
    insight_type = "ApiCallRateInsight"
  }

  insight_selector {
    insight_type = "ApiErrorRateInsight"
  }

  tags = {
    "enterprise-app-id" = "governance-001"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-SECURITY-001"
    "data-classification" = "confidential"
  }
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/enterprise/cloudtrail/management"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.cloudtrail.arn

  tags = {
    "enterprise-app-id" = "governance-001"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-SECURITY-001"
  }
}

# ── CloudTrail S3 bucket ──────────────────────────────────────────────────────

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "enterprise-cloudtrail-logs-${var.log_archive_account_id}"
  force_destroy = false

  tags = {
    "enterprise-app-id" = "governance-001"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-SECURITY-001"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  versioning_configuration {
    status = "Enabled"  # SOX-04 S3 versioning for state integrity
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cloudtrail.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket                  = aws_s3_bucket.cloudtrail_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 2555  # 7 years retention — SOX/PCI compliance
    }
  }
}

resource "aws_s3_bucket_logging" "cloudtrail_logs" {
  bucket        = aws_s3_bucket.cloudtrail_logs.id
  target_bucket = aws_s3_bucket.cloudtrail_logs.id
  target_prefix = "access-logs/"
}

# ── CloudTrail KMS key ────────────────────────────────────────────────────────

resource "aws_kms_key" "cloudtrail" {
  description             = "KMS key for CloudTrail log encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  multi_region            = false

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.management_account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudTrail to encrypt logs"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action = ["kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource = "*"
      }
    ]
  })

  tags = {
    "enterprise-app-id" = "governance-001"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-SECURITY-001"
  }
}

resource "aws_kms_alias" "cloudtrail" {
  name          = "alias/enterprise-cloudtrail"
  target_key_id = aws_kms_key.cloudtrail.key_id
}

# ── CloudWatch Metric Alarms ──────────────────────────────────────────────────
# SOX-06: Alarms for unauthorized access attempts

resource "aws_cloudwatch_metric_alarm" "root_account_login" {
  alarm_name          = "enterprise-root-account-login"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "RootAccountLoginCount"
  namespace           = "Enterprise/Security"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "SOX/PCI: Root account login detected"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  ok_actions          = [aws_sns_topic.security_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = {
    "enterprise-app-id" = "governance-001"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-SECURITY-001"
  }
}

resource "aws_cloudwatch_metric_alarm" "unauthorized_api_calls" {
  alarm_name          = "enterprise-unauthorized-api-calls"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnauthorizedAPICallCount"
  namespace           = "Enterprise/Security"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "SOX/PCI: Unauthorized API calls detected"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "iam_policy_changes" {
  alarm_name          = "enterprise-iam-policy-changes"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "IAMPolicyChangeCount"
  namespace           = "Enterprise/Security"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "SOX: IAM policy change detected — segregation of duties enforcement"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "cloudtrail_changes" {
  alarm_name          = "enterprise-cloudtrail-changes"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CloudTrailChangeCount"
  namespace           = "Enterprise/Security"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "SOX/HIPAA: CloudTrail configuration changed — audit log integrity"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "console_signin_without_mfa" {
  alarm_name          = "enterprise-console-signin-no-mfa"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ConsoleSigninWithoutMFACount"
  namespace           = "Enterprise/Security"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "HIPAA/PCI: Console login without MFA"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "s3_bucket_policy_changes" {
  alarm_name          = "enterprise-s3-policy-changes"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "S3BucketPolicyChangeCount"
  namespace           = "Enterprise/Security"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "PCI/GDPR: S3 bucket policy changed — data protection monitoring"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "security_group_changes" {
  alarm_name          = "enterprise-security-group-changes"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "SecurityGroupChangeCount"
  namespace           = "Enterprise/Security"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "PCI: Security group change detected"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}

# ── SNS Alerting ──────────────────────────────────────────────────────────────

resource "aws_sns_topic" "security_alerts" {
  name              = "enterprise-security-alerts"
  kms_master_key_id = aws_kms_key.cloudtrail.arn
  display_name      = "Enterprise Security Alerts"

  tags = {
    "enterprise-app-id" = "governance-001"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-SECURITY-001"
  }
}

resource "aws_sns_topic" "compliance_alerts" {
  name              = "enterprise-compliance-alerts"
  kms_master_key_id = aws_kms_key.cloudtrail.arn
  display_name      = "Enterprise Compliance Alerts"
}

# ── GuardDuty (organization-wide) ─────────────────────────────────────────────
# PCI-05, GDPR-04: GuardDuty for continuous threat detection

resource "aws_guardduty_detector" "primary" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = {
    "enterprise-app-id" = "governance-001"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-SECURITY-001"
  }
}

resource "aws_guardduty_organization_configuration" "primary" {
  auto_enable_organization_members = "ALL"
  detector_id                      = aws_guardduty_detector.primary.id

  datasources {
    s3_logs { auto_enable = true }
    kubernetes {
      audit_logs { enable = true }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes { auto_enable = true }
      }
    }
  }
}

# ── Security Hub (organization-wide) ──────────────────────────────────────────
# PCI-05, HIPAA-06: Security Hub for aggregated findings

resource "aws_securityhub_account" "primary" {}

resource "aws_securityhub_organization_configuration" "primary" {
  auto_enable           = true
  auto_enable_standards = "DEFAULT"
  depends_on            = [aws_securityhub_account.primary]
}

resource "aws_securityhub_standards_subscription" "aws_foundational" {
  standards_arn = "arn:aws:securityhub:us-east-1::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.primary]
}

resource "aws_securityhub_standards_subscription" "pci_dss" {
  standards_arn = "arn:aws:securityhub:us-east-1::standards/pci-dss/v/3.2.1"
  depends_on    = [aws_securityhub_account.primary]
}

resource "aws_securityhub_standards_subscription" "cis_aws" {
  standards_arn = "arn:aws:securityhub:us-east-1::standards/cis-aws-foundations-benchmark/v/1.4.0"
  depends_on    = [aws_securityhub_account.primary]
}

resource "aws_securityhub_action_target" "critical_findings" {
  name        = "Send-Critical-Findings-to-SNS"
  identifier  = "CriticalFindingsToSNS"
  description = "HIPAA/PCI: Send critical Security Hub findings to SNS for breach notification"
  depends_on  = [aws_securityhub_account.primary]
}

# ── Amazon Macie (GDPR personal data discovery) ───────────────────────────────
# GDPR-04, GDPR-06: Macie for sensitive data discovery

resource "aws_macie2_account" "primary" {
  finding_publishing_frequency = "FIFTEEN_MINUTES"
  status                       = "ENABLED"
}

resource "aws_macie2_organization_admin_account" "primary" {
  admin_account_id = var.audit_account_id
  depends_on       = [aws_macie2_account.primary]
}

resource "aws_macie2_classification_job" "data_discovery" {
  name       = "enterprise-pii-discovery"
  job_type   = "SCHEDULED"
  depends_on = [aws_macie2_account.primary]

  schedule_frequency {
    weekly_schedule = "MONDAY"
  }

  s3_job_definition {
    bucket_definitions {
      account_id = var.management_account_id
      buckets    = ["enterprise-data-*", "enterprise-pii-*"]
    }
  }

  sampling_percentage = 100
}

# ── IAM Access Analyzer ───────────────────────────────────────────────────────

resource "aws_accessanalyzer_analyzer" "organization" {
  analyzer_name = "enterprise-organization-analyzer"
  type          = "ORGANIZATION"

  tags = {
    "enterprise-app-id" = "governance-001"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-SECURITY-001"
  }
}

# ── AWS Config (organization-wide) ────────────────────────────────────────────

resource "aws_config_configuration_recorder" "primary" {
  name     = "enterprise-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "primary" {
  name           = "enterprise-config-delivery"
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs.id
  s3_key_prefix  = "aws-config"

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.primary]
}

resource "aws_config_configuration_recorder_status" "primary" {
  name       = aws_config_configuration_recorder.primary.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.primary]
}

# Config rules for compliance
resource "aws_config_config_rule" "encrypted_volumes" {
  name        = "encrypted-volumes"
  description = "PCI/HIPAA: Checks all EBS volumes are encrypted"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }
  depends_on = [aws_config_configuration_recorder_status.primary]
}

resource "aws_config_config_rule" "root_mfa_enabled" {
  name        = "root-account-mfa-enabled"
  description = "SOX/HIPAA: Checks root account has MFA enabled"

  source {
    owner             = "AWS"
    source_identifier = "ROOT_ACCOUNT_MFA_ENABLED"
  }
  depends_on = [aws_config_configuration_recorder_status.primary]
}

resource "aws_config_config_rule" "s3_bucket_ssl_only" {
  name        = "s3-bucket-ssl-requests-only"
  description = "HIPAA: Checks S3 buckets require SSL"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SSL_REQUESTS_ONLY"
  }
  depends_on = [aws_config_configuration_recorder_status.primary]
}

resource "aws_config_config_rule" "restricted_ssh" {
  name        = "restricted-ssh"
  description = "PCI: Checks SG rules do not allow unrestricted SSH"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
  depends_on = [aws_config_configuration_recorder_status.primary]
}

resource "aws_config_config_rule" "cloud_trail_enabled" {
  name        = "cloudtrail-enabled"
  description = "SOX/PCI: CloudTrail must be enabled organization-wide"

  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_ENABLED"
  }
  depends_on = [aws_config_configuration_recorder_status.primary]
}

resource "aws_config_config_rule" "required_tags" {
  name        = "required-tags"
  description = "SOX/Governance: All resources must have enterprise-app-id, environment, cost-center"

  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }

  input_parameters = jsonencode({
    tag1Key = "enterprise-app-id"
    tag2Key = "environment"
    tag3Key = "cost-center"
    tag4Key = "managed-by"
  })

  depends_on = [aws_config_configuration_recorder_status.primary]
}

resource "aws_config_config_rule" "vpc_flow_logs_enabled" {
  name        = "vpc-flow-logs-enabled"
  description = "PCI-04: VPC flow logs must be enabled"

  source {
    owner             = "AWS"
    source_identifier = "VPC_FLOW_LOGS_ENABLED"
  }
  depends_on = [aws_config_configuration_recorder_status.primary]
}

resource "aws_config_config_rule" "guardduty_enabled" {
  name        = "guardduty-enabled-centralized"
  description = "PCI/GDPR: GuardDuty must be enabled"

  source {
    owner             = "AWS"
    source_identifier = "GUARDDUTY_ENABLED_CENTRALIZED"
  }
  depends_on = [aws_config_configuration_recorder_status.primary]
}

# ── IAM roles for CloudTrail/Config ───────────────────────────────────────────

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "enterprise-cloudtrail-cloudwatch-role"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    "enterprise-app-id" = "governance-001"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-SECURITY-001"
  }
}

resource "aws_iam_role" "config" {
  name = "enterprise-config-role"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config_managed" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# ── Backup Policy ─────────────────────────────────────────────────────────────
# HIPAA-04: AWS Backup for all accounts in org

resource "aws_backup_vault" "enterprise" {
  name        = "enterprise-backup-vault"
  kms_key_arn = aws_kms_key.cloudtrail.arn

  tags = {
    "enterprise-app-id" = "governance-001"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-SECURITY-001"
  }
}

resource "aws_backup_plan" "enterprise" {
  name = "enterprise-backup-plan"

  rule {
    rule_name         = "daily-backup-30-day-retention"
    target_vault_name = aws_backup_vault.enterprise.name
    schedule          = "cron(0 2 * * ? *)"
    start_window      = 60
    completion_window = 120

    lifecycle {
      delete_after = 30
    }
  }

  rule {
    rule_name         = "weekly-backup-1-year-retention"
    target_vault_name = aws_backup_vault.enterprise.name
    schedule          = "cron(0 3 ? * SUN *)"
    start_window      = 60
    completion_window = 360

    lifecycle {
      cold_storage_after = 30
      delete_after       = 365
    }
  }

  rule {
    rule_name         = "monthly-backup-7-year-retention"
    target_vault_name = aws_backup_vault.enterprise.name
    schedule          = "cron(0 4 1 * ? *)"
    start_window      = 60
    completion_window = 480

    lifecycle {
      cold_storage_after = 90
      delete_after       = 2555
    }
  }

  tags = {
    "enterprise-app-id" = "governance-001"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-SECURITY-001"
  }
}

resource "aws_backup_selection" "all_tagged_resources" {
  name         = "enterprise-all-tagged-resources"
  plan_id      = aws_backup_plan.enterprise.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "enterprise-app-id"
    value = "*"
  }
}

resource "aws_iam_role" "backup" {
  name = "enterprise-backup-role"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup_managed" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# ── SSO / OIDC Federation ─────────────────────────────────────────────────────
# HIPAA-01, PCI-03: No long-term IAM user credentials — SSO federation

resource "aws_ssoadmin_instance_access_control_attributes" "primary" {
  instance_arn = tolist(data.aws_ssoadmin_instances.primary.arns)[0]

  attribute {
    key = "email"
    value {
      source = ["$${path:email}"]
    }
  }

  attribute {
    key = "department"
    value {
      source = ["$${path:custom:department}"]
    }
  }

  attribute {
    key = "cost-center"
    value {
      source = ["$${path:custom:costCenter}"]
    }
  }
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = {
    "enterprise-app-id" = "governance-001"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-001"
  }
}

data "aws_ssoadmin_instances" "primary" {}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "log_archive_account_id" {
  type        = string
  description = "AWS Log Archive account ID"
}

variable "management_account_id" {
  type        = string
  description = "AWS Management account ID"
}

variable "audit_account_id" {
  type        = string
  description = "AWS Security Audit account ID"
}

variable "permissions_boundary_arn" {
  type        = string
  description = "ARN of the enterprise permissions boundary policy"
}
