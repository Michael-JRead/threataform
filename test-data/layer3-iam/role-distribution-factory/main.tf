# layer3-iam/role-distribution-factory/main.tf
# Layer 3 — IAM Management: role-distribution-factory (rdf)
# Distributes IAM roles across accounts and OUs at scale via factory pattern
# Detection signals: role-distribution, role_distribution, roledist, rdf, iam-factory, role_dist_factory

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "enterprise-terraform-state-production"
    key            = "iam/role-distribution-factory/terraform.tfstate"
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
      "enterprise-app-id" = "role-distribution-factory"
      "environment"       = var.environment
      "managed-by"        = "terraform"
      "cost-center"       = "CC-PLATFORM-003"
    }
  }
}

data "aws_caller_identity" "current" {}

# ── role-distribution-factory (rdf): Cross-Account Role Distribution ──────────
# Variables: role_template, target_accounts, target_ous, distribution_scope

locals {
  rdf_role_name_prefix = "rdf"
  roledist_prefix      = "role-distribution"

  # Target accounts for distribution (Enterprise-CIB-Prod-Workload-001 pattern)
  target_account_ids = concat(
    var.target_accounts,
    data.aws_organizations_organizational_unit_descendant_accounts.workloads.accounts[*].id,
  )
}

data "aws_organizations_organizational_unit_descendant_accounts" "workloads" {
  parent_id = var.workloads_ou_id
}

data "aws_organizations_organizational_unit_descendant_accounts" "platform" {
  parent_id = var.platform_ou_id
}

# ── CloudFormation StackSet for role distribution (cross-account) ─────────────

resource "aws_cloudformation_stack_set" "enterprise_baseline_roles" {
  name             = "enterprise-baseline-roles-distribution"
  description      = "role-distribution-factory (rdf): distributes enterprise baseline IAM roles to all member accounts"
  permission_model = "SERVICE_MANAGED"
  call_as          = "DELEGATED_ADMIN"

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  capabilities = ["CAPABILITY_NAMED_IAM"]

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description = "role-distribution-factory: Enterprise baseline IAM roles"

    Resources = {
      ReadOnlyAuditRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          RoleName = "enterprise-readonly-audit"
          Description = "roledist: Read-only audit role distributed by role-distribution-factory"
          MaxSessionDuration = 3600
          PermissionsBoundary = { Fn_ImportValue = "EnterprisePermissionsBoundaryArn" }
          AssumeRolePolicyDocument = {
            Version = "2012-10-17"
            Statement = [{
              Effect = "Allow"
              Principal = {
                AWS = var.audit_account_role_arns
              }
              Action = "sts:AssumeRole"
              Condition = {
                Bool = { "aws:MultiFactorAuthPresent" = "true" }
              }
            }]
          }
          ManagedPolicyArns = [
            "arn:aws:iam::aws:policy/ReadOnlyAccess",
            "arn:aws:iam::aws:policy/SecurityAudit",
          ]
          Tags = [
            { Key = "enterprise-app-id", Value = "role-distribution-factory" }
            { Key = "managed-by", Value = "terraform" }
            { Key = "role-type", Value = "audit" }
            { Key = "rdf", Value = "true" }
          ]
        }
      }

      SecurityBreakGlassRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          RoleName = "enterprise-security-break-glass"
          Description = "role-distribution-factory: Emergency break-glass role for security incident response"
          MaxSessionDuration = 3600
          AssumeRolePolicyDocument = {
            Version = "2012-10-17"
            Statement = [{
              Effect = "Allow"
              Principal = { AWS = var.security_team_role_arns }
              Action   = ["sts:AssumeRole", "sts:TagSession"]
              Condition = {
                Bool = { "aws:MultiFactorAuthPresent" = "true" }
                StringEquals = { "aws:PrincipalOrgID" = var.organization_id }
              }
            }]
          }
          ManagedPolicyArns = [
            "arn:aws:iam::aws:policy/AdministratorAccess",
          ]
          Tags = [
            { Key = "enterprise-app-id", Value = "role-distribution-factory" }
            { Key = "managed-by", Value = "terraform" }
            { Key = "role-type", Value = "break-glass" }
            { Key = "rdf", Value = "true" }
          ]
        }
      }

      TerraformExecutionRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          RoleName = "enterprise-terraform-execution"
          Description = "rdf: Terraform execution role distributed via role-distribution-factory to all accounts"
          MaxSessionDuration = 3600
          AssumeRolePolicyDocument = {
            Version = "2012-10-17"
            Statement = [{
              Effect = "Allow"
              Principal = {
                AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/enterprise-terraform-pipeline"
              }
              Action = "sts:AssumeRole"
              Condition = {
                StringEquals = { "aws:PrincipalOrgID" = var.organization_id }
              }
            }]
          }
          ManagedPolicyArns = [
            "arn:aws:iam::aws:policy/AdministratorAccess",
          ]
          Tags = [
            { Key = "enterprise-app-id", Value = "role-distribution-factory" }
            { Key = "managed-by", Value = "terraform" }
            { Key = "role-type", Value = "terraform-execution" }
            { Key = "roledist", Value = "true" }
          ]
        }
      }

      ConfigRecorderRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          RoleName = "enterprise-config-recorder"
          Description = "rdf: Config recorder role — governance baseline via role-distribution-factory"
          AssumeRolePolicyDocument = {
            Version = "2012-10-17"
            Statement = [{
              Effect    = "Allow"
              Principal = { Service = "config.amazonaws.com" }
              Action    = "sts:AssumeRole"
            }]
          }
          ManagedPolicyArns = [
            "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
          ]
          Tags = [
            { Key = "enterprise-app-id", Value = "role-distribution-factory" }
            { Key = "managed-by", Value = "terraform" }
            { Key = "role-type", Value = "config-recorder" }
          ]
        }
      }
    }
  })

  tags = {
    "enterprise-app-id"    = "role-distribution-factory"
    "environment"          = var.environment
    "managed-by"           = "terraform"
    "cost-center"          = "CC-PLATFORM-003"
    "factory-type"         = "iam-factory"
    "role-dist-factory"    = "rdf"
    "role_distribution"    = "true"
  }
}

resource "aws_cloudformation_stack_set_instance" "baseline_roles_workloads" {
  stack_set_name = aws_cloudformation_stack_set.enterprise_baseline_roles.name
  call_as        = "DELEGATED_ADMIN"

  deployment_targets {
    organizational_unit_ids = [var.workloads_ou_id, var.platform_ou_id]
  }

  operation_preferences {
    failure_tolerance_percentage = 20
    max_concurrent_percentage    = 25
    region_concurrency_type      = "SEQUENTIAL"
  }
}

# ── DynamoDB: role distribution audit table ────────────────────────────────────

resource "aws_dynamodb_table" "role_distribution_audit" {
  name         = "enterprise-role-distribution-audit"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "AccountId"
  range_key    = "DistributionTimestamp"

  attribute {
    name = "AccountId"
    type = "S"
  }

  attribute {
    name = "DistributionTimestamp"
    type = "S"
  }

  attribute {
    name = "RoleName"
    type = "S"
  }

  global_secondary_index {
    name            = "RoleNameIndex"
    hash_key        = "RoleName"
    range_key       = "DistributionTimestamp"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    "enterprise-app-id" = "role-distribution-factory"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-003"
    "factory-type"      = "iam-factory"
    "rdf"               = "true"
  }
}

# ── SSM: distribution scope registry ──────────────────────────────────────────

resource "aws_ssm_parameter" "rdf_distribution_scope" {
  name  = "/enterprise/role-distribution-factory/distribution-scope"
  type  = "String"
  value = jsonencode({
    distributionScope    = var.distribution_scope
    roleTemplate         = var.role_template
    targetOUs            = var.target_ous
    stackSetName         = aws_cloudformation_stack_set.enterprise_baseline_roles.name
    lastDistribution     = "2026-03-10T00:00:00Z"
    managedRoles = [
      "enterprise-readonly-audit",
      "enterprise-security-break-glass",
      "enterprise-terraform-execution",
      "enterprise-config-recorder",
    ]
  })

  tags = {
    "enterprise-app-id" = "role-distribution-factory"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-003"
    "rdf"               = "true"
    "roledist"          = "true"
  }
}

# ── SNS: distribution event notifications ─────────────────────────────────────

resource "aws_sns_topic" "role_distribution_events" {
  name              = "enterprise-role-distribution-events"
  kms_master_key_id = var.kms_key_id

  tags = {
    "enterprise-app-id" = "role-distribution-factory"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-003"
  }
}

# ── Outputs (role-distribution-factory standard outputs) ──────────────────────

output "distributed_role_arns" {
  description = "rdf output: distributed_role_arns — ARNs of all distributed roles"
  value = {
    audit_role       = "arn:aws:iam::*:role/enterprise-readonly-audit"
    break_glass_role = "arn:aws:iam::*:role/enterprise-security-break-glass"
    terraform_role   = "arn:aws:iam::*:role/enterprise-terraform-execution"
    config_role      = "arn:aws:iam::*:role/enterprise-config-recorder"
  }
}

output "distribution_report" {
  description = "rdf output: distribution_report — StackSet ARN and deployment status"
  value = {
    stackset_name    = aws_cloudformation_stack_set.enterprise_baseline_roles.name
    stackset_id      = aws_cloudformation_stack_set.enterprise_baseline_roles.id
    distribution_scope = var.distribution_scope
    target_ous       = var.target_ous
  }
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region" { type = string; default = "us-east-1" }
variable "environment" { type = string; default = "production" }
variable "organization_id" { type = string; description = "AWS Organization ID" }
variable "workloads_ou_id" { type = string; description = "ID of the Workloads OU" }
variable "platform_ou_id" { type = string; description = "ID of the Platform OU" }
variable "audit_account_role_arns" { type = list(string); description = "ARNs from audit account allowed to assume readonly role" }
variable "security_team_role_arns" { type = list(string); description = "Security team ARNs for break-glass role" }
variable "role_template" { type = string; description = "rdf: role_template — which template set to distribute"; default = "baseline" }
variable "target_accounts" { type = list(string); description = "rdf: target_accounts — explicit account IDs"; default = [] }
variable "target_ous" { type = list(string); description = "rdf: target_ous — OU IDs to distribute roles to"; default = [] }
variable "distribution_scope" { type = string; description = "rdf: distribution_scope — OU|ACCOUNT|ORGANIZATION"; default = "OU" }
variable "kms_key_arn" { type = string; description = "KMS key ARN for DynamoDB encryption" }
variable "kms_key_id" { type = string; description = "KMS key ID for SNS encryption" }
