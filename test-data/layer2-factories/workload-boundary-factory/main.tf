# layer2-factories/workload-boundary-factory/main.tf
# Layer 2 — Platform Factory: workload-boundary-factory (wbf)
# Provisions workload-specific isolation contexts for application teams
# Detection signals: workload-boundary, workload_boundary, WorkloadBoundary, wbf, workload-context

terraform {
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.0" }
  }
  backend "s3" {
    bucket         = "enterprise-terraform-state-production"
    key            = "factories/workload-boundary-factory/terraform.tfstate"
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
      "enterprise-app-id" = "workload-boundary-factory"
      "environment"       = var.environment
      "managed-by"        = "terraform"
      "cost-center"       = "CC-PLATFORM-002"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_eks_cluster" "controlplane" { name = var.eks_cluster_name }

# ── IRSA — IAM Role for Service Account (workload-boundary-sa) ────────────────

resource "aws_iam_role" "workload_boundary_operator" {
  name                 = "controlplane-workload-boundary"
  description          = "IRSA role for workload-boundary-factory (wbf) operator — team isolation contexts"
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
          "${replace(data.aws_eks_cluster.controlplane.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:workload-boundary-factory:workload-boundary-sa"
          "${replace(data.aws_eks_cluster.controlplane.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    "enterprise-app-id" = "workload-boundary-factory"
    "factory-type"      = "workload-boundary"
    "irsa-sa"           = "workload-boundary-sa"
    "workload-context"  = "wbf"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-002"
  }
}

resource "aws_iam_policy" "workload_boundary_operator" {
  name        = "workload-boundary-factory-policy"
  description = "IAM policy for workload-boundary-factory (wbf) — workload namespace/account isolation"
  path        = "/controlplane/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "OrganizationsWorkloadScoping"
        Effect = "Allow"
        Action = [
          "organizations:AttachPolicy", "organizations:DetachPolicy",
          "organizations:ListPoliciesForTarget",
          "organizations:ListAccountsForParent",
          "organizations:DescribeAccount",
          "organizations:TagResource", "organizations:UntagResource",
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMWorkloadContext"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:TagRole", "iam:UntagRole",
          "iam:GetRole", "iam:ListRolePolicies",
        ]
        Resource = [
          "arn:aws:iam::*:role/workload-boundary-*",
          "arn:aws:iam::*:role/wbf-*",
        ]
      },
      {
        Sid    = "EKSNamespaceIsolation"
        Effect = "Allow"
        Action = [
          "eks:AccessKubernetesApi",
          "eks:Describe*",
          "eks:List*",
        ]
        Resource = "*"
      },
      {
        Sid    = "CrossAccountAssume"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = "arn:aws:iam::*:role/workload-boundary-factory-*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "workload_boundary_operator" {
  role       = aws_iam_role.workload_boundary_operator.name
  policy_arn = aws_iam_policy.workload_boundary_operator.arn
}

# ── Kubernetes Service Account ────────────────────────────────────────────────

resource "kubernetes_namespace" "workload_boundary_factory" {
  metadata {
    name = "workload-boundary-factory"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "factory-type"                 = "workload-boundary"
      "wbf"                          = "true"
      "workload-context"             = "true"
    }
  }
}

resource "kubernetes_service_account" "workload_boundary_sa" {
  metadata {
    name      = "workload-boundary-sa"
    namespace = kubernetes_namespace.workload_boundary_factory.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn"               = aws_iam_role.workload_boundary_operator.arn
      "eks.amazonaws.com/token-expiration"       = "86400"
      "eks.amazonaws.com/sts-regional-endpoints" = "true"
    }
    labels = {
      "app.kubernetes.io/name"      = "workload-boundary-factory"
      "app.kubernetes.io/component" = "operator"
      "factory-type"                = "workload-boundary"
      "wbf"                         = "true"
    }
  }
}

# ── RBAC ─────────────────────────────────────────────────────────────────────

resource "kubernetes_cluster_role" "workload_boundary_operator" {
  metadata {
    name = "workload-boundary-operator"
    labels = { "factory-type" = "workload-boundary", "wbf" = "true" }
  }

  rule {
    api_groups = ["enterprise.io"]
    resources  = ["workloadboundaries", "workloadcontexts", "teamboundaries"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["enterprise.io"]
    resources  = ["workloadboundaries/status", "teamboundaries/status"]
    verbs      = ["get", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "resourcequotas", "limitranges"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }

  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["networkpolicies"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_cluster_role_binding" "workload_boundary_operator" {
  metadata { name = "workload-boundary-operator" }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.workload_boundary_operator.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.workload_boundary_sa.metadata[0].name
    namespace = kubernetes_namespace.workload_boundary_factory.metadata[0].name
  }
}

# ── CRD: WorkloadBoundary ────────────────────────────────────────────────────

resource "kubernetes_manifest" "crd_workload_boundary" {
  manifest = {
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata = {
      name = "workloadboundaries.enterprise.io"
      labels = { "factory-type" = "workload-boundary-factory", "wbf" = "true" }
    }
    spec = {
      group = "enterprise.io"
      names = {
        kind       = "WorkloadBoundary"
        listKind   = "WorkloadBoundaryList"
        plural     = "workloadboundaries"
        singular   = "workloadboundary"
        shortNames = ["wbf", "workload-context"]
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
                  teamName             = { type = "string" }
                  accountId            = { type = "string" }
                  networkBoundaryRef   = { type = "string" }
                  portfolioBoundaryRef = { type = "string" }
                  workloadContext = {
                    type = "object"
                    properties = {
                      namespace          = { type = "string" }
                      cpuLimit           = { type = "string" }
                      memoryLimit        = { type = "string" }
                      storageLimit       = { type = "string" }
                      allowedNamespaces  = { type = "array", items = { type = "string" } }
                    }
                  }
                  scpIds             = { type = "array", items = { type = "string" } }
                  teamScopedPolicies = { type = "array", items = { type = "string" } }
                  complianceLevel    = { type = "string", enum = ["STANDARD", "PCI", "HIPAA", "SOX"] }
                }
                required = ["teamName", "accountId"]
              }
              status = {
                type = "object"
                properties = {
                  phase              = { type = "string" }
                  namespaceCreated   = { type = "boolean" }
                  scpAttached        = { type = "boolean" }
                  networkPoliciesApplied = { type = "boolean" }
                  lastReconcileTime  = { type = "string" }
                }
              }
            }
          }
        }
        subresources = { status = {} }
      }]
    }
  }
}

resource "kubernetes_manifest" "crd_team_boundary" {
  manifest = {
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata = {
      name = "teamboundaries.enterprise.io"
      labels = { "factory-type" = "workload-boundary-factory", "wbf" = "true" }
    }
    spec = {
      group = "enterprise.io"
      names = {
        kind     = "TeamBoundary"
        plural   = "teamboundaries"
        singular = "teamboundary"
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
                  workloadBoundaryRef  = { type = "string" }
                  teamId               = { type = "string" }
                  costCenter           = { type = "string" }
                  dataClassification   = { type = "string" }
                  allowEgressInternet  = { type = "boolean" }
                  allowedServicePorts  = { type = "array", items = { type = "integer" } }
                }
              }
            }
          }
        }
        subresources = { status = {} }
      }]
    }
  }
}

# ── Outputs / Variables ───────────────────────────────────────────────────────

output "workload_boundary_role_arn" {
  value = aws_iam_role.workload_boundary_operator.arn
}

output "workload_boundary_sa_name" {
  value = kubernetes_service_account.workload_boundary_sa.metadata[0].name
}

variable "aws_region" { type = string; default = "us-east-1" }
variable "environment" { type = string; default = "production" }
variable "eks_cluster_name" { type = string }
variable "permissions_boundary_arn" { type = string }
