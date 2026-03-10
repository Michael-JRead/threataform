# layer3-iam/module-role/main.tf
# Layer 3 — IAM Management: module-role (iam-role-module)
# Centralized IAM role creation with trust policies, permissions boundaries, cross-account access
# Detection signals: module-role, module_role, iam-role-module, role-module

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "enterprise-terraform-state-production"
    key            = "iam/module-role/terraform.tfstate"
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
data "aws_partition" "current" {}

# ── Module: module-role — role creation pattern ───────────────────────────────
# module-role variables: service_name, app_id, roles_to_assume, trusted_roles,
#                        trusted_services, permissions_boundary

locals {
  role_name         = "enterprise-${var.service_name}-${var.environment}-role"
  policy_name_prefix = "enterprise-${var.service_name}"

  # Trust policy construction — module-role standard pattern
  trusted_service_statements = [
    for svc in var.trusted_services : {
      Effect    = "Allow"
      Principal = { Service = svc }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:RequestedRegion" = var.aws_region
        }
      }
    }
  ]

  trusted_role_statements = [
    for role_arn in var.trusted_roles : {
      Effect    = "Allow"
      Principal = { AWS = role_arn }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = {
          "sts:TransitiveTagKeys" = ["enterprise-app-id", "cost-center"]
        }
        BoolIfExists = {
          "aws:MultiFactorAuthPresent" = "true"
        }
      }
    }
  ]

  assume_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = concat(local.trusted_service_statements, local.trusted_role_statements)
  })
}

# ── IAM Roles (examples of module-role pattern) ───────────────────────────────

# SOX-01: IAM roles separate for deploy/admin/audit
resource "aws_iam_role" "deploy" {
  name                 = "${local.role_name}-deploy"
  description          = "module-role: Deploy role for ${var.service_name} — least privilege CI/CD"
  permissions_boundary = var.permissions_boundary_arn
  path                 = "/enterprise/${var.service_name}/"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowGitHubActions"
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:enterprise-org/${var.service_name}:environment:${var.environment}"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "role-type"         = "deploy"
    "module"            = "module-role"
    "service-name"      = var.service_name
  }
}

resource "aws_iam_role" "admin" {
  name                 = "${local.role_name}-admin"
  description          = "module-role: Admin role for ${var.service_name} — break-glass elevated access"
  permissions_boundary = var.permissions_boundary_arn
  path                 = "/enterprise/${var.service_name}/"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowRoleAssumption"
      Effect = "Allow"
      Principal = { AWS = var.admin_role_arns }
      Action = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        Bool = { "aws:MultiFactorAuthPresent" = "true" }
        StringEquals = {
          "sts:TransitiveTagKeys" = ["enterprise-app-id", "environment"]
        }
      }
    }]
  })

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "role-type"         = "admin"
    "module"            = "module-role"
  }
}

resource "aws_iam_role" "audit" {
  name                 = "${local.role_name}-audit"
  description          = "module-role: Audit role for ${var.service_name} — read-only SOX audit access"
  permissions_boundary = var.permissions_boundary_arn
  path                 = "/enterprise/${var.service_name}/"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowAuditRoleAssumption"
      Effect = "Allow"
      Principal = { AWS = var.audit_role_arns }
      Action    = "sts:AssumeRole"
      Condition = {
        Bool = { "aws:MultiFactorAuthPresent" = "true" }
      }
    }]
  })

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "role-type"         = "audit"
    "module"            = "module-role"
  }
}

resource "aws_iam_role" "application" {
  name                 = "${local.role_name}-app"
  description          = "module-role: Application runtime role for ${var.service_name}"
  permissions_boundary = var.permissions_boundary_arn
  path                 = "/enterprise/${var.service_name}/"
  max_session_duration = 3600

  assume_role_policy = local.assume_policy

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "role-type"         = "application"
    "module"            = "module-role"
    "service-name"      = var.service_name
  }
}

# Cross-account role for roles_to_assume pattern
resource "aws_iam_role" "cross_account" {
  count                = length(var.roles_to_assume) > 0 ? 1 : 0
  name                 = "${local.role_name}-cross-account"
  description          = "module-role: Cross-account assume for ${var.service_name} — trusted relationships"
  permissions_boundary = var.permissions_boundary_arn
  path                 = "/enterprise/${var.service_name}/"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [for role_arn in var.roles_to_assume : {
      Effect    = "Allow"
      Principal = { AWS = role_arn }
      Action    = ["sts:AssumeRole", "sts:SetSourceIdentity"]
      Condition = {
        StringEquals = { "aws:PrincipalOrgID" = var.organization_id }
      }
    }]
  })

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "role-type"         = "cross-account"
    "module"            = "module-role"
  }
}

# ── Policies ──────────────────────────────────────────────────────────────────

resource "aws_iam_policy" "deploy_policy" {
  name        = "${local.policy_name_prefix}-deploy-policy"
  description = "module-role: Least-privilege deploy policy for ${var.service_name}"
  path        = "/enterprise/${var.service_name}/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability", "ecr:PutImage",
          "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload", "ecr:GetAuthorizationToken",
        ]
        Resource = [
          "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.service_name}",
          "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.service_name}-*",
        ]
      },
      {
        Sid    = "ECSDeployments"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService", "ecs:RegisterTaskDefinition",
          "ecs:DescribeServices", "ecs:DescribeTaskDefinition",
          "ecs:DescribeTasks", "ecs:ListTasks",
          "ecs:RunTask",
        ]
        Resource = [
          "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/*/${var.service_name}*",
          "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task-definition/${var.service_name}*",
        ]
      },
      {
        Sid    = "LambdaDeploy"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration",
          "lambda:PublishVersion", "lambda:CreateAlias", "lambda:UpdateAlias",
          "lambda:GetFunction", "lambda:ListVersionsByFunction",
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.service_name}*"
      },
      {
        Sid    = "SSMParameterRead"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/enterprise/${var.service_name}/*"
      },
      {
        Sid    = "KMSSigningVerification"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey"]
        Resource = var.kms_key_arns
      }
    ]
  })

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
  }
}

resource "aws_iam_policy" "audit_policy" {
  name        = "${local.policy_name_prefix}-audit-policy"
  description = "module-role: Read-only audit policy for ${var.service_name} — SOX compliance"
  path        = "/enterprise/${var.service_name}/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadOnlyAudit"
      Effect   = "Allow"
      Action   = ["*:Describe*", "*:List*", "*:Get*", "cloudtrail:LookupEvents", "logs:FilterLogEvents"]
      Resource = "*"
      Condition = {
        StringEquals = {
          "aws:RequestedRegion" = var.aws_region
        }
      }
    }]
  })
}

# ── Policy Attachments ────────────────────────────────────────────────────────

resource "aws_iam_role_policy_attachment" "deploy_policy" {
  role       = aws_iam_role.deploy.name
  policy_arn = aws_iam_policy.deploy_policy.arn
}

resource "aws_iam_role_policy_attachment" "deploy_readonly" {
  role       = aws_iam_role.deploy.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "audit_policy" {
  role       = aws_iam_role.audit.name
  policy_arn = aws_iam_policy.audit_policy.arn
}

resource "aws_iam_role_policy_attachment" "admin_admin" {
  role       = aws_iam_role.admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ── Instance Profile (for EC2 application role) ───────────────────────────────

resource "aws_iam_instance_profile" "application" {
  name = "${local.role_name}-app-profile"
  role = aws_iam_role.application.name

  tags = {
    "enterprise-app-id" = var.app_id
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = var.cost_center
    "module"            = "module-role"
  }
}

# ── Outputs ── (module-role standard outputs) ─────────────────────────────────

output "role_arn" {
  description = "module-role output: ARN of the application runtime role"
  value       = aws_iam_role.application.arn
}

output "role_name" {
  description = "module-role output: Name of the application runtime role"
  value       = aws_iam_role.application.name
}

output "instance_profile_arn" {
  description = "module-role output: ARN of the EC2 instance profile"
  value       = aws_iam_instance_profile.application.arn
}

output "deploy_role_arn" {
  description = "module-role output: ARN of the deploy role"
  value       = aws_iam_role.deploy.arn
}

output "admin_role_arn" {
  description = "module-role output: ARN of the admin (break-glass) role"
  value       = aws_iam_role.admin.arn
}

output "audit_role_arn" {
  description = "module-role output: ARN of the SOX audit role"
  value       = aws_iam_role.audit.arn
}

output "cross_account_role_arn" {
  description = "module-role output: ARN of the cross-account assume role"
  value       = length(aws_iam_role.cross_account) > 0 ? aws_iam_role.cross_account[0].arn : null
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "service_name" {
  type        = string
  description = "module-role: service_name — used for naming and tagging"
}

variable "app_id" {
  type        = string
  description = "module-role: app_id — enterprise-app-id tag value"
}

variable "environment" {
  type        = string
  description = "module-role: environment — production|staging|development"
  default     = "production"
}

variable "trusted_services" {
  type        = list(string)
  description = "module-role: trusted_services — AWS service principals that can assume the role"
  default     = []
}

variable "trusted_roles" {
  type        = list(string)
  description = "module-role: trusted_roles — IAM role ARNs that can assume this role"
  default     = []
}

variable "roles_to_assume" {
  type        = list(string)
  description = "module-role: roles_to_assume — ARNs of cross-account roles this role can assume"
  default     = []
}

variable "admin_role_arns" {
  type        = list(string)
  description = "ARNs allowed to assume the admin (break-glass) role"
  default     = []
}

variable "audit_role_arns" {
  type        = list(string)
  description = "ARNs allowed to assume the SOX audit role"
  default     = []
}

variable "permissions_boundary_arn" {
  type        = string
  description = "module-role: permissions_boundary — ARN of the permissions boundary policy"
}

variable "kms_key_arns" {
  type        = list(string)
  description = "KMS key ARNs the deploy role can use"
  default     = ["*"]
}

variable "organization_id" {
  type        = string
  description = "AWS Organization ID for cross-account trust conditions"
  default     = ""
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cost_center" {
  type    = string
  default = "CC-PLATFORM-003"
}
