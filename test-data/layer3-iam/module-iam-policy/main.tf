# layer3-iam/module-iam-policy/main.tf
# Layer 3 — IAM Management: module-iam-policy (iam-policy-module)
# Centralized IAM policy authoring with SDLC controls and version management
# Detection signals: module-iam-policy, iam_policy_module, iam-policy-module, module_iam_policy

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "enterprise-terraform-state-production"
    key            = "iam/module-iam-policy/terraform.tfstate"
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
      "enterprise-app-id" = "iam-policy-catalog"
      "environment"       = var.environment
      "managed-by"        = "terraform"
      "cost-center"       = "CC-PLATFORM-003"
    }
  }
}

# ── module-iam-policy: Policy Catalog ────────────────────────────────────────
# Centralized policy authoring — each policy has policy_name, policy_document,
# description, path, tags (as per IAM_MODULES spec)

# Platform Permissions Boundary
resource "aws_iam_policy" "enterprise_permissions_boundary" {
  name        = "enterprise-permissions-boundary"
  description = "module-iam-policy: Enterprise-wide permissions boundary — maximum permission set for all roles"
  path        = "/enterprise/boundaries/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCoreServices"
        Effect = "Allow"
        Action = [
          "s3:*", "ec2:*", "ecs:*", "eks:*",
          "lambda:*", "rds:*", "elasticache:*",
          "kms:*", "secretsmanager:*", "ssm:*",
          "logs:*", "cloudwatch:*", "cloudtrail:*",
          "iam:Get*", "iam:List*", "iam:PassRole",
          "sts:AssumeRole", "sts:GetCallerIdentity",
          "sns:*", "sqs:*",
          "backup:*", "config:*",
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyBoundaryMutation"
        Effect = "Deny"
        Action = [
          "iam:CreatePolicy", "iam:DeletePolicy",
          "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
          "iam:SetDefaultPolicyVersion",
          "iam:DeleteRolePermissionsBoundary",
          "iam:PutRolePermissionsBoundary",
          "iam:CreateRole", "iam:DeleteRole",
        ]
        Resource = "arn:aws:iam::*:policy/enterprise/boundaries/*"
      },
      {
        Sid    = "DenyOrgModification"
        Effect = "Deny"
        Action = ["organizations:*"]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:PrincipalArn" = [
              "arn:aws:iam::*:role/OrganizationAccountAccessRole",
              "arn:aws:iam::*:role/controlplane-portfolio-boundary",
            ]
          }
        }
      }
    ]
  })

  tags = {
    "enterprise-app-id" = "iam-policy-catalog"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-003"
    "policy-type"       = "boundary"
    "module"            = "module-iam-policy"
  }
}

# Read-only catalog policy
resource "aws_iam_policy" "enterprise_readonly" {
  name        = "enterprise-readonly-access"
  description = "module-iam-policy: Enterprise-wide read-only access for audit and observability"
  path        = "/enterprise/catalog/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadOnlyAll"
      Effect = "Allow"
      Action = [
        "*:Describe*", "*:List*", "*:Get*",
        "cloudtrail:LookupEvents",
        "logs:FilterLogEvents", "logs:GetLogEvents",
        "config:Get*", "config:Describe*", "config:List*",
        "health:Describe*",
        "support:Describe*",
        "ce:Get*", "ce:Describe*",
        "budgets:ViewBudget", "budgets:Describe*",
        "trustedadvisor:Describe*",
      ]
      Resource = "*"
    }]
  })

  tags = {
    "enterprise-app-id" = "iam-policy-catalog"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-003"
    "policy-type"       = "catalog"
    "module"            = "module-iam-policy"
  }
}

# Platform Engineering policy
resource "aws_iam_policy" "platform_engineering" {
  name        = "enterprise-platform-engineering"
  description = "module-iam-policy: Platform Engineering team — manage factories and control plane"
  path        = "/enterprise/catalog/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = ["s3:*", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = [
          "arn:aws:s3:::enterprise-terraform-state-*",
          "arn:aws:s3:::enterprise-terraform-state-*/*",
          "arn:aws:dynamodb:*:*:table/terraform-state-lock*",
        ]
      },
      {
        Sid    = "EKSControlPlane"
        Effect = "Allow"
        Action = ["eks:*", "ec2:Describe*", "iam:PassRole"]
        Resource = "*"
      },
      {
        Sid    = "FactoryManagement"
        Effect = "Allow"
        Action = [
          "organizations:*",
          "controltower:*",
          "sso:*",
          "ssoadmin:*",
          "identitystore:*",
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsAccess"
        Effect = "Allow"
        Action = ["secretsmanager:*", "ssm:*", "kms:*"]
        Resource = [
          "arn:aws:secretsmanager:*:*:secret:enterprise/platform/*",
          "arn:aws:ssm:*:*:parameter/enterprise/*",
          "arn:aws:kms:*:*:key/*",
        ]
      }
    ]
  })
}

# Data Engineering policy
resource "aws_iam_policy" "data_engineering" {
  name        = "enterprise-data-engineering"
  description = "module-iam-policy: Data Engineering team — analytics, ETL, data lake access"
  path        = "/enterprise/catalog/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3DataLake"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::enterprise-data-lake-*",
          "arn:aws:s3:::enterprise-data-lake-*/*",
        ]
      },
      {
        Sid    = "GlueAndAthena"
        Effect = "Allow"
        Action = ["glue:*", "athena:*", "lakeformation:*"]
        Resource = "*"
      },
      {
        Sid    = "RedshiftAccess"
        Effect = "Allow"
        Action = ["redshift:*", "redshift-data:*", "redshift-serverless:*"]
        Resource = "*"
      },
      {
        Sid    = "EMRAndKinesis"
        Effect = "Allow"
        Action = ["elasticmapreduce:*", "kinesis:*", "firehose:*"]
        Resource = "*"
      },
      {
        Sid    = "KMSDataKeys"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = "arn:aws:kms:*:*:key/*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = [
              "s3.us-east-1.amazonaws.com",
              "glue.us-east-1.amazonaws.com",
              "athena.us-east-1.amazonaws.com",
            ]
          }
        }
      }
    ]
  })
}

# Security Engineering policy
resource "aws_iam_policy" "security_engineering" {
  name        = "enterprise-security-engineering"
  description = "module-iam-policy: Security Engineering — security tools, compliance, WAF, GuardDuty"
  path        = "/enterprise/catalog/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecurityServices"
        Effect = "Allow"
        Action = [
          "guardduty:*", "securityhub:*", "macie2:*",
          "inspector2:*", "access-analyzer:*",
          "wafv2:*", "waf:*", "waf-regional:*",
          "shield:*", "fms:*",
          "detective:*",
        ]
        Resource = "*"
      },
      {
        Sid    = "ComplianceTools"
        Effect = "Allow"
        Action = [
          "config:*", "cloudtrail:*",
          "health:*", "trustedadvisor:*",
        ]
        Resource = "*"
      },
      {
        Sid    = "KMSKeyAdmin"
        Effect = "Allow"
        Action = ["kms:*"]
        Resource = "*"
      },
      {
        Sid    = "SecretsAdmin"
        Effect = "Allow"
        Action = ["secretsmanager:*"]
        Resource = "arn:aws:secretsmanager:*:*:secret:enterprise/*"
      }
    ]
  })
}

# ── Policy version tracking (SDLC) ────────────────────────────────────────────

resource "aws_ssm_parameter" "policy_catalog_version" {
  name  = "/enterprise/iam-policy-catalog/version"
  type  = "String"
  value = "3.2.1"

  tags = {
    "enterprise-app-id" = "iam-policy-catalog"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-003"
    "module"            = "module-iam-policy"
  }
}

resource "aws_ssm_parameter" "policy_catalog_registry" {
  name  = "/enterprise/iam-policy-catalog/registry"
  type  = "String"
  value = jsonencode({
    version = "3.2.1"
    policies = [
      { name = "enterprise-permissions-boundary", type = "boundary", arn = aws_iam_policy.enterprise_permissions_boundary.arn },
      { name = "enterprise-readonly-access", type = "catalog", arn = aws_iam_policy.enterprise_readonly.arn },
      { name = "enterprise-platform-engineering", type = "catalog", arn = aws_iam_policy.platform_engineering.arn },
      { name = "enterprise-data-engineering", type = "catalog", arn = aws_iam_policy.data_engineering.arn },
      { name = "enterprise-security-engineering", type = "catalog", arn = aws_iam_policy.security_engineering.arn },
    ]
  })
}

# ── Outputs (module-iam-policy standard outputs) ──────────────────────────────

output "policy_arn" {
  description = "module-iam-policy output: ARN of the primary policy"
  value       = aws_iam_policy.enterprise_permissions_boundary.arn
}

output "policy_id" {
  description = "module-iam-policy output: ID of the primary policy"
  value       = aws_iam_policy.enterprise_permissions_boundary.policy_id
}

output "policy_name" {
  description = "module-iam-policy output: Name of the primary policy"
  value       = aws_iam_policy.enterprise_permissions_boundary.name
}

output "permissions_boundary_arn" {
  description = "ARN for use as permissions_boundary_arn in module-role"
  value       = aws_iam_policy.enterprise_permissions_boundary.arn
}

output "catalog_policy_arns" {
  description = "Map of policy name → ARN for all catalog policies"
  value = {
    boundary            = aws_iam_policy.enterprise_permissions_boundary.arn
    readonly            = aws_iam_policy.enterprise_readonly.arn
    platform_engineering = aws_iam_policy.platform_engineering.arn
    data_engineering    = aws_iam_policy.data_engineering.arn
    security_engineering = aws_iam_policy.security_engineering.arn
  }
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region" { type = string; default = "us-east-1" }
variable "environment" { type = string; default = "production" }
