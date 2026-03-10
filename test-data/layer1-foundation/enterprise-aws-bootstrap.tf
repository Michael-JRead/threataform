# layer1-foundation/enterprise-aws-bootstrap.tf
# Layer 1 — Foundation: AWS Organization, OUs, SCPs, baseline governance
# enterprise-aws-bootstrap  |  xsphere-aws-bootstrap

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "enterprise-terraform-state-bootstrap"
    key            = "foundation/bootstrap/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
    kms_key_id     = "alias/enterprise-tfstate-key"
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      "enterprise-app-id"     = "bootstrap-001"
      "environment"           = "management"
      "managed-by"            = "terraform"
      "cost-center"           = "CC-PLATFORM-001"
      "data-classification"   = "confidential"
    }
  }
}

# ── AWS Organization ─────────────────────────────────────────────────────────

resource "aws_organizations_organization" "root" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "sso.amazonaws.com",
    "controltower.amazonaws.com",
    "securityhub.amazonaws.com",
    "guardduty.amazonaws.com",
    "macie.amazonaws.com",
    "access-analyzer.amazonaws.com",
    "backup.amazonaws.com",
    "ram.amazonaws.com",
  ]

  feature_set = "ALL"

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
    "BACKUP_POLICY",
    "RESOURCE_CONTROL_POLICY",
  ]
}

# ── Organizational Units ──────────────────────────────────────────────────────
# ou-tree.yaml definitions translated to Terraform

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.root.roots[0].id
  tags = {
    "enterprise-app-id" = "bootstrap-001"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-001"
  }
}

resource "aws_organizations_organizational_unit" "infrastructure" {
  name      = "Infrastructure"
  parent_id = aws_organizations_organization.root.roots[0].id
  tags = {
    "enterprise-app-id" = "bootstrap-001"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-001"
  }
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = aws_organizations_organization.root.roots[0].id
  tags = {
    "enterprise-app-id" = "bootstrap-001"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-001"
  }
}

resource "aws_organizations_organizational_unit" "sandbox" {
  name      = "Sandbox"
  parent_id = aws_organizations_organization.root.roots[0].id
}

resource "aws_organizations_organizational_unit" "workloads_prod" {
  name      = "Enterprise-CIB-Prod-Workload-001"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_organizational_unit" "workloads_nonprod" {
  name      = "Enterprise-Platform-NonProd-Shared-001"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_organizational_unit" "platform" {
  name      = "Platform"
  parent_id = aws_organizations_organizational_unit.infrastructure.id
}

resource "aws_organizations_organizational_unit" "shared_services" {
  name      = "SharedServices"
  parent_id = aws_organizations_organizational_unit.infrastructure.id
}

# ── Service Control Policies (SCP templates) ─────────────────────────────────
# templates/scp/*.yaml equivalent

resource "aws_organizations_policy" "deny_region_outside_approved" {
  name        = "DenyRegionOutsideApproved"
  description = "SCP: Deny all actions in unapproved AWS regions (GDPR data residency)"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnapprovedRegions"
        Effect    = "Deny"
        NotAction = [
          "a4b:*", "acm:*", "aws-marketplace-management:*",
          "aws-marketplace:*", "budgets:*", "ce:*",
          "chime:*", "cloudfront:*", "config:*",
          "cur:*", "directconnect:*", "ec2:Describe*",
          "fms:*", "globalaccelerator:*", "health:*",
          "iam:*", "importexport:*", "kms:*",
          "mobileanalytics:*", "networkmanager:*",
          "organizations:*", "pricing:*", "route53:*",
          "route53domains:*", "s3:GetBucketPublicAccessBlock",
          "shield:*", "sts:*", "support:*",
          "trustedadvisor:*", "waf:*", "waf-regional:*", "wafv2:*"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = ["us-east-1", "us-west-2", "eu-west-1"]
          }
        }
      }
    ]
  })

  tags = {
    "enterprise-app-id" = "bootstrap-001"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-001"
  }
}

resource "aws_organizations_policy" "deny_root_account_usage" {
  name        = "DenyRootAccountUsage"
  description = "SCP: Prevent root account usage — SOX access control segregation"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyRootUser"
      Effect   = "Deny"
      Action   = "*"
      Resource = "*"
      Condition = {
        StringLike = {
          "aws:PrincipalArn" = ["arn:aws:iam::*:root"]
        }
      }
    }]
  })
}

resource "aws_organizations_policy" "deny_public_s3" {
  name        = "DenyPublicS3"
  description = "SCP: Deny making any S3 bucket public — PCI data protection"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyPublicS3Acls"
        Effect = "Deny"
        Action = [
          "s3:PutBucketAcl",
          "s3:PutObjectAcl",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = ["public-read", "public-read-write", "authenticated-read"]
          }
        }
      },
      {
        Sid    = "DenyPublicS3Policy"
        Effect = "Deny"
        Action = ["s3:PutBucketPublicAccessBlock"]
        Resource = "*"
        Condition = {
          Bool = { "s3:PublicAccessBlockConfiguration" = "false" }
        }
      }
    ]
  })
}

resource "aws_organizations_policy" "require_imdsv2" {
  name        = "RequireIMDSv2"
  description = "SCP: Enforce IMDSv2 on all EC2 instances — PCI SSRF prevention"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyIMDSv1"
      Effect = "Deny"
      Action = "ec2:RunInstances"
      Resource = "arn:aws:ec2:*:*:instance/*"
      Condition = {
        StringNotEquals = {
          "ec2:MetadataHttpTokens" = "required"
        }
      }
    }]
  })
}

resource "aws_organizations_policy" "require_mfa" {
  name        = "RequireMFA"
  description = "SCP: Deny non-SSO actions without MFA — HIPAA unique identification"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyWithoutMFA"
      Effect = "Deny"
      NotAction = [
        "iam:CreateVirtualMFADevice",
        "iam:EnableMFADevice",
        "iam:GetUser",
        "iam:ListMFADevices",
        "iam:ResyncMFADevice",
        "sts:GetSessionToken",
      ]
      Resource = "*"
      Condition = {
        BoolIfExists = {
          "aws:MultiFactorAuthPresent" = "false"
        }
      }
    }]
  })
}

resource "aws_organizations_policy" "enforce_encryption" {
  name        = "EnforceEncryptionAtRest"
  description = "SCP: Require KMS encryption for EBS, RDS, S3 — PCI/HIPAA encryption mandate"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyUnencryptedEBS"
        Effect = "Deny"
        Action = "ec2:RunInstances"
        Resource = "arn:aws:ec2:*:*:volume/*"
        Condition = {
          Bool = { "ec2:Encrypted" = "false" }
        }
      },
      {
        Sid    = "DenyUnencryptedRDS"
        Effect = "Deny"
        Action = "rds:CreateDBInstance"
        Resource = "*"
        Condition = {
          Bool = { "rds:StorageEncrypted" = "false" }
        }
      }
    ]
  })
}

resource "aws_organizations_policy" "deny_iam_user_creation" {
  name        = "DenyIAMUserCreation"
  description = "SCP: Block creating long-term IAM user credentials — PCI/HIPAA SSO enforcement"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyIAMUserCreation"
      Effect   = "Deny"
      Action   = ["iam:CreateUser", "iam:CreateAccessKey"]
      Resource = "*"
      Condition = {
        StringNotEquals = {
          "aws:PrincipalOrgID" = var.organization_id
        }
      }
    }]
  })
}

# ── SCP Attachments ────────────────────────────────────────────────────────────

resource "aws_organizations_policy_attachment" "deny_region_workloads" {
  policy_id = aws_organizations_policy.deny_region_outside_approved.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_policy_attachment" "deny_root_all" {
  policy_id = aws_organizations_policy.deny_root_account_usage.id
  target_id = aws_organizations_organization.root.roots[0].id
}

resource "aws_organizations_policy_attachment" "deny_public_s3_workloads" {
  policy_id = aws_organizations_policy.deny_public_s3.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_policy_attachment" "require_imdsv2_workloads" {
  policy_id = aws_organizations_policy.require_imdsv2.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_policy_attachment" "deny_iam_user_workloads" {
  policy_id = aws_organizations_policy.deny_iam_user_creation.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

# ── Tag Policy ────────────────────────────────────────────────────────────────

resource "aws_organizations_policy" "mandatory_tags" {
  name        = "MandatoryEnterpriseTags"
  description = "TAG POLICY: Enforce enterprise-app-id, environment, cost-center, managed-by"
  type        = "TAG_POLICY"

  content = jsonencode({
    tags = {
      "enterprise-app-id" = {
        tag_key = {
          @@assign = "enterprise-app-id"
        }
      }
      "environment" = {
        tag_key = { @@assign = "environment" }
        tag_value = {
          @@assign = ["production", "staging", "development", "sandbox", "management"]
        }
      }
      "cost-center" = {
        tag_key = { @@assign = "cost-center" }
      }
      "managed-by" = {
        tag_key = { @@assign = "managed-by" }
        tag_value = { @@assign = ["terraform", "cloudformation"] }
      }
    }
  })
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "organization_id" {
  type        = string
  description = "AWS Organization ID (o-xxxxxxxxxxxx)"
}

variable "management_account_id" {
  type        = string
  description = "AWS Management account ID"
}

variable "audit_account_id" {
  type        = string
  description = "AWS Security Audit account ID"
}

variable "log_archive_account_id" {
  type        = string
  description = "AWS Log Archive account ID"
}
