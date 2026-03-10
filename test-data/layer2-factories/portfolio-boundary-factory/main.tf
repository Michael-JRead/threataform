# layer2-factories/portfolio-boundary-factory/main.tf
# Layer 2 — Platform Factory: portfolio-boundary-factory (pbf)
# Kubernetes operator managing AWS organizational portfolio boundaries, OUs, and policy scopes
# Detection signals: portfolio-boundary, portfolio_boundary, PortfolioBoundary, pbf

terraform {
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.0" }
    helm       = { source = "hashicorp/helm", version = "~> 2.0" }
  }
  backend "s3" {
    bucket         = "enterprise-terraform-state-production"
    key            = "factories/portfolio-boundary-factory/terraform.tfstate"
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
      "enterprise-app-id" = "portfolio-boundary-factory"
      "environment"       = var.environment
      "managed-by"        = "terraform"
      "cost-center"       = "CC-PLATFORM-002"
    }
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.controlplane.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.controlplane.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.controlplane.name]
  }
}

# ── EKS Data Sources ──────────────────────────────────────────────────────────

data "aws_eks_cluster" "controlplane" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "controlplane" {
  name = var.eks_cluster_name
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── IRSA — IAM Role for Service Account (portfolio-boundary-sa) ───────────────
# IRSA pattern: IAM role bound to Kubernetes service account via OIDC

resource "aws_iam_role" "portfolio_boundary_operator" {
  name                 = "controlplane-portfolio-boundary"
  description          = "IRSA role for portfolio-boundary-factory operator — manages OU/SCP lifecycle"
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
          "${replace(data.aws_eks_cluster.controlplane.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:portfolio-boundary-factory:portfolio-boundary-sa"
          "${replace(data.aws_eks_cluster.controlplane.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    "enterprise-app-id" = "portfolio-boundary-factory"
    "factory-type"      = "portfolio-boundary"
    "irsa-sa"           = "portfolio-boundary-sa"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-002"
  }
}

resource "aws_iam_policy" "portfolio_boundary_operator" {
  name        = "portfolio-boundary-factory-policy"
  description = "IAM policy for portfolio-boundary-factory operator — pbf"
  path        = "/controlplane/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "OrganizationsReadWrite"
        Effect = "Allow"
        Action = [
          "organizations:CreateOrganizationalUnit",
          "organizations:DeleteOrganizationalUnit",
          "organizations:UpdateOrganizationalUnit",
          "organizations:ListOrganizationalUnitsForParent",
          "organizations:DescribeOrganizationalUnit",
          "organizations:MoveAccount",
          "organizations:CreatePolicy",
          "organizations:UpdatePolicy",
          "organizations:DeletePolicy",
          "organizations:AttachPolicy",
          "organizations:DetachPolicy",
          "organizations:ListPolicies",
          "organizations:DescribePolicy",
          "organizations:ListTargetsForPolicy",
          "organizations:ListPoliciesForTarget",
          "organizations:ListDelegatedAdministrators",
          "organizations:RegisterDelegatedAdministrator",
        ]
        Resource = "*"
      },
      {
        Sid    = "ControlTowerRead"
        Effect = "Allow"
        Action = [
          "controltower:ListLandingZones",
          "controltower:GetLandingZone",
          "controltower:ListEnabledControls",
          "controltower:GetEnabledControl",
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMParameterAccess"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter",
          "ssm:DeleteParameter",
        ]
        Resource = "arn:aws:ssm:*:*:parameter/enterprise/portfolio-boundary/*"
      }
    ]
  })

  tags = {
    "enterprise-app-id" = "portfolio-boundary-factory"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-002"
  }
}

resource "aws_iam_role_policy_attachment" "portfolio_boundary_operator" {
  role       = aws_iam_role.portfolio_boundary_operator.name
  policy_arn = aws_iam_policy.portfolio_boundary_operator.arn
}

# ── Kubernetes Service Account (IRSA binding) ─────────────────────────────────

resource "kubernetes_namespace" "portfolio_boundary_factory" {
  metadata {
    name = "portfolio-boundary-factory"
    labels = {
      "app.kubernetes.io/managed-by"   = "terraform"
      "factory-type"                   = "portfolio-boundary"
      "security.enterprise.io/enabled" = "true"
    }
  }
}

resource "kubernetes_service_account" "portfolio_boundary_sa" {
  metadata {
    name      = "portfolio-boundary-sa"
    namespace = kubernetes_namespace.portfolio_boundary_factory.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn"               = aws_iam_role.portfolio_boundary_operator.arn
      "eks.amazonaws.com/token-expiration"       = "86400"
      "eks.amazonaws.com/sts-regional-endpoints" = "true"
    }
    labels = {
      "app.kubernetes.io/name"       = "portfolio-boundary-factory"
      "app.kubernetes.io/component"  = "operator"
      "factory-type"                 = "portfolio-boundary"
    }
  }
}

# ── RBAC for portfolio-boundary operator ─────────────────────────────────────

resource "kubernetes_cluster_role" "portfolio_boundary_operator" {
  metadata {
    name = "portfolio-boundary-operator"
    labels = {
      "factory-type" = "portfolio-boundary"
    }
  }

  rule {
    api_groups = ["enterprise.io"]
    resources  = ["portfolioboundaries", "boundaryrequests", "boundaryaccounts"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["enterprise.io"]
    resources  = ["portfolioboundaries/status", "boundaryrequests/status"]
    verbs      = ["get", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["events", "configmaps", "secrets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }

  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_cluster_role_binding" "portfolio_boundary_operator" {
  metadata {
    name = "portfolio-boundary-operator"
    labels = {
      "factory-type" = "portfolio-boundary"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.portfolio_boundary_operator.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.portfolio_boundary_sa.metadata[0].name
    namespace = kubernetes_namespace.portfolio_boundary_factory.metadata[0].name
  }
}

# ── CRD: PortfolioBoundary ────────────────────────────────────────────────────

resource "kubernetes_manifest" "crd_portfolio_boundary" {
  manifest = {
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata = {
      name = "portfolioboundaries.enterprise.io"
      labels = {
        "factory-type" = "portfolio-boundary-factory"
        "pbf"          = "true"
      }
    }
    spec = {
      group = "enterprise.io"
      names = {
        kind     = "PortfolioBoundary"
        listKind = "PortfolioBoundaryList"
        plural   = "portfolioboundaries"
        singular = "portfolioboundary"
        shortNames = ["pbf", "pb"]
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
                  organizationalUnitId  = { type = "string" }
                  portfolioName         = { type = "string" }
                  scpIds                = { type = "array", items = { type = "string" } }
                  boundaryScope         = { type = "string", enum = ["OU", "ACCOUNT", "ROOT"] }
                  targetAccountIds      = { type = "array", items = { type = "string" } }
                  controlTowerEnabled   = { type = "boolean" }
                  complianceFrameworks  = { type = "array", items = { type = "string" } }
                  tags = {
                    type = "object"
                    additionalProperties = { type = "string" }
                  }
                }
                required = ["organizationalUnitId", "portfolioName", "boundaryScope"]
              }
              status = {
                type = "object"
                properties = {
                  phase            = { type = "string" }
                  message          = { type = "string" }
                  lastReconcileTime = { type = "string" }
                  boundaryArn      = { type = "string" }
                  ouId             = { type = "string" }
                  managedScpIds    = { type = "array", items = { type = "string" } }
                }
              }
            }
          }
        }
        subresources = { status = {} }
        additionalPrinterColumns = [
          { name = "Portfolio", type = "string", jsonPath = ".spec.portfolioName" },
          { name = "Scope", type = "string", jsonPath = ".spec.boundaryScope" },
          { name = "Phase", type = "string", jsonPath = ".status.phase" },
        ]
      }]
    }
  }
}

# ── CRD: BoundaryAccount ─────────────────────────────────────────────────────

resource "kubernetes_manifest" "crd_boundary_account" {
  manifest = {
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata = {
      name = "boundaryaccounts.enterprise.io"
      labels = {
        "factory-type" = "portfolio-boundary-factory"
        "pbf"          = "true"
      }
    }
    spec = {
      group = "enterprise.io"
      names = {
        kind     = "BoundaryAccount"
        listKind = "BoundaryAccountList"
        plural   = "boundaryaccounts"
        singular = "boundaryaccount"
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
                  accountId          = { type = "string" }
                  portfolioBoundaryRef = { type = "string" }
                  enrolmentState     = { type = "string" }
                  delegatedAdmin     = { type = "boolean" }
                }
                required = ["accountId", "portfolioBoundaryRef"]
              }
            }
          }
        }
        subresources = { status = {} }
      }]
    }
  }
}

# ── SSM parameters for operator state ────────────────────────────────────────

resource "aws_ssm_parameter" "portfolio_boundary_config" {
  name        = "/enterprise/portfolio-boundary/operator-config"
  type        = "SecureString"
  value       = jsonencode({
    rekeyIntervalHours    = 24
    maxBoundariesPerOU    = 5
    allowedScpAttachments = ["governance", "security", "compliance"]
    auditBucketName       = "enterprise-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"
  })
  key_id      = var.kms_key_arn

  tags = {
    "enterprise-app-id" = "portfolio-boundary-factory"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-002"
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "portfolio_boundary_role_arn" {
  description = "IRSA IAM role ARN for portfolio-boundary-factory operator"
  value       = aws_iam_role.portfolio_boundary_operator.arn
}

output "portfolio_boundary_sa_name" {
  description = "Kubernetes service account name (portfolio-boundary-sa)"
  value       = kubernetes_service_account.portfolio_boundary_sa.metadata[0].name
}

output "portfolio_boundary_namespace" {
  description = "Kubernetes namespace for portfolio-boundary-factory"
  value       = kubernetes_namespace.portfolio_boundary_factory.metadata[0].name
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "eks_cluster_name" {
  type        = string
  description = "Name of the EKS control plane cluster"
}

variable "permissions_boundary_arn" {
  type        = string
  description = "ARN of the enterprise permissions boundary policy"
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the KMS key for SSM parameter encryption"
}
