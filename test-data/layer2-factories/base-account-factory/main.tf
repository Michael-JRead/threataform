# layer2-factories/base-account-factory/main.tf
# Layer 2 — Platform Factory: base-account-factory (baf)
# Account vending machine — creates new AWS accounts with baseline security config
# Detection signals: base-account, base_account, BaselineAccount, baf, account-factory, account_factory

terraform {
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.0" }
  }
  backend "s3" {
    bucket         = "enterprise-terraform-state-production"
    key            = "factories/base-account-factory/terraform.tfstate"
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
      "enterprise-app-id" = "base-account-factory"
      "environment"       = var.environment
      "managed-by"        = "terraform"
      "cost-center"       = "CC-PLATFORM-002"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_eks_cluster" "controlplane" { name = var.eks_cluster_name }

# ── IRSA — IAM Role for Service Account (base-account-sa) ────────────────────

resource "aws_iam_role" "base_account_operator" {
  name                 = "controlplane-base-account"
  description          = "IRSA role for base-account-factory (baf) operator — account vending machine"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.controlplane.identity[0].oidc[0].issuer, "https://", "")}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(data.aws_eks_cluster.controlplane.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:base-account-factory:base-account-sa"
          "${replace(data.aws_eks_cluster.controlplane.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    "enterprise-app-id" = "base-account-factory"
    "factory-type"      = "base-account"
    "irsa-sa"           = "base-account-sa"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-002"
    "account-factory"   = "baf"
  }
}

resource "aws_iam_policy" "base_account_operator" {
  name        = "base-account-factory-policy"
  description = "IAM policy for base-account-factory (account-factory/baf) operator"
  path        = "/controlplane/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AccountVending"
        Effect = "Allow"
        Action = [
          "organizations:CreateAccount",
          "organizations:DescribeCreateAccountStatus",
          "organizations:MoveAccount",
          "organizations:TagResource",
          "organizations:UntagResource",
          "organizations:ListAccountsForParent",
          "organizations:DescribeAccount",
        ]
        Resource = "*"
      },
      {
        Sid    = "ControlTowerEnrollment"
        Effect = "Allow"
        Action = [
          "controltower:EnrollAccount",
          "controltower:UpdateEnabledBaseline",
          "controltower:EnableBaseline",
          "controltower:DisableBaseline",
          "controltower:GetEnabledBaseline",
          "controltower:ListEnabledBaselines",
          "controltower:ResetEnabledBaseline",
        ]
        Resource = "*"
      },
      {
        Sid    = "AccountBaselineSSO"
        Effect = "Allow"
        Action = [
          "sso:CreateAccountAssignment",
          "sso:DeleteAccountAssignment",
          "sso:ListAccountAssignments",
          "sso:DescribeAccountAssignmentCreationStatus",
          "sso:ListPermissionSets",
          "sso:DescribePermissionSet",
        ]
        Resource = "*"
      },
      {
        Sid    = "CrossAccountAssumeForBaseline"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = "arn:aws:iam::*:role/AWSControlTowerExecution"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "base_account_operator" {
  role       = aws_iam_role.base_account_operator.name
  policy_arn = aws_iam_policy.base_account_operator.arn
}

# ── Kubernetes Service Account ────────────────────────────────────────────────

resource "kubernetes_namespace" "base_account_factory" {
  metadata {
    name = "base-account-factory"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "factory-type"                 = "base-account"
      "baf"                          = "true"
      "account-factory"              = "true"
    }
  }
}

resource "kubernetes_service_account" "base_account_sa" {
  metadata {
    name      = "base-account-sa"
    namespace = kubernetes_namespace.base_account_factory.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn"               = aws_iam_role.base_account_operator.arn
      "eks.amazonaws.com/token-expiration"       = "86400"
      "eks.amazonaws.com/sts-regional-endpoints" = "true"
    }
    labels = {
      "app.kubernetes.io/name"      = "base-account-factory"
      "app.kubernetes.io/component" = "operator"
      "factory-type"                = "base-account"
      "baf"                         = "true"
    }
  }
}

# ── CRD: AccountFactory / BaselineAccount / AccountVending ───────────────────

resource "kubernetes_manifest" "crd_account_factory" {
  manifest = {
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata = {
      name = "accountfactories.enterprise.io"
      labels = {
        "factory-type"   = "base-account-factory"
        "baf"            = "true"
        "account-factory" = "true"
      }
    }
    spec = {
      group = "enterprise.io"
      names = {
        kind       = "AccountFactory"
        listKind   = "AccountFactoryList"
        plural     = "accountfactories"
        singular   = "accountfactory"
        shortNames = ["baf", "acctfactory"]
      }
      scope = "Cluster"
      versions = [{
        name    = "v1alpha1"
        served  = true
        storage = true
        schema = {
          openAPIV3Schema = {
            type = "object"
            properties = {
              spec = {
                type = "object"
                properties = {
                  accountName        = { type = "string" }
                  accountEmail       = { type = "string", format = "email" }
                  organizationalUnit = { type = "string" }
                  businessUnit       = { type = "string" }
                  environment        = { type = "string", enum = ["production", "staging", "development", "sandbox"] }
                  purpose            = { type = "string" }
                  accountNaming = {
                    type = "object"
                    description = "Enterprise naming pattern: {Platform}-{BusinessUnit}-{Environment}-{Purpose}-{Sequence}"
                    properties = {
                      platform  = { type = "string" }
                      sequence  = { type = "integer" }
                    }
                  }
                  baselineConfig = {
                    type = "object"
                    properties = {
                      enableCloudTrail      = { type = "boolean", default = true }
                      enableGuardDuty       = { type = "boolean", default = true }
                      enableSecurityHub     = { type = "boolean", default = true }
                      enableConfig          = { type = "boolean", default = true }
                      enableAccessAnalyzer  = { type = "boolean", default = true }
                      enableMacie           = { type = "boolean", default = true }
                      ssoPermissionSets     = { type = "array", items = { type = "string" } }
                      scpPolicies           = { type = "array", items = { type = "string" } }
                    }
                  }
                  networkConfig = {
                    type = "object"
                    properties = {
                      networkBoundaryRef  = { type = "string" }
                      vpcCidr             = { type = "string" }
                      connectToTGW        = { type = "boolean" }
                    }
                  }
                  tags = { type = "object", additionalProperties = { type = "string" } }
                }
                required = ["accountName", "accountEmail", "organizationalUnit", "environment"]
              }
              status = {
                type = "object"
                properties = {
                  phase         = { type = "string" }
                  accountId     = { type = "string" }
                  accountArn    = { type = "string" }
                  baselineState = { type = "string" }
                  ssoAssignments = { type = "array", items = { type = "string" } }
                  lastReconcileTime = { type = "string" }
                  createAccountRequestId = { type = "string" }
                }
              }
            }
          }
        }
        subresources = { status = {} }
        additionalPrinterColumns = [
          { name = "Account",     type = "string", jsonPath = ".status.accountId" },
          { name = "Environment", type = "string", jsonPath = ".spec.environment" },
          { name = "Phase",       type = "string", jsonPath = ".status.phase" },
          { name = "Age",         type = "date",   jsonPath = ".metadata.creationTimestamp" },
        ]
      }]
    }
  }
}

resource "kubernetes_manifest" "crd_baseline_account" {
  manifest = {
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata = {
      name = "baselineaccounts.enterprise.io"
      labels = { "factory-type" = "base-account-factory", "baf" = "true" }
    }
    spec = {
      group = "enterprise.io"
      names = {
        kind     = "BaselineAccount"
        plural   = "baselineaccounts"
        singular = "baselineaccount"
      }
      scope = "Cluster"
      versions = [{
        name    = "v1alpha1"
        served  = true
        storage = true
        schema = {
          openAPIV3Schema = {
            type = "object"
            properties = {
              spec = {
                type = "object"
                properties = {
                  accountId         = { type = "string" }
                  accountFactoryRef = { type = "string" }
                  baselineVersion   = { type = "string" }
                  complianceTarget  = { type = "array", items = { type = "string" } }
                }
                required = ["accountId"]
              }
            }
          }
        }
        subresources = { status = {} }
      }]
    }
  }
}

# ── SSM parameters for vended account registry ────────────────────────────────

resource "aws_ssm_parameter" "account_registry_config" {
  name   = "/enterprise/base-account-factory/config"
  type   = "SecureString"
  value  = jsonencode({
    managementAccountId    = data.aws_caller_identity.current.account_id
    defaultOrganizationId  = var.organization_id
    baselineVersion        = "2.0.0"
    defaultScpPolicies     = ["DenyRegionOutsideApproved", "DenyRootAccountUsage", "RequireIMDSv2"]
    auditAccount           = var.audit_account_id
    logArchiveAccount      = var.log_archive_account_id
  })
  key_id = var.kms_key_arn

  tags = {
    "enterprise-app-id" = "base-account-factory"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-002"
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "base_account_role_arn" {
  value = aws_iam_role.base_account_operator.arn
}

output "base_account_sa_name" {
  value = kubernetes_service_account.base_account_sa.metadata[0].name
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region" { type = string; default = "us-east-1" }
variable "environment" { type = string; default = "production" }
variable "eks_cluster_name" { type = string }
variable "permissions_boundary_arn" { type = string }
variable "kms_key_arn" { type = string }
variable "organization_id" { type = string }
variable "audit_account_id" { type = string }
variable "log_archive_account_id" { type = string }
