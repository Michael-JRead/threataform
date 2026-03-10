# layer2-factories/network-boundary-factory/main.tf
# Layer 2 — Platform Factory: network-boundary-factory (nbf)
# Kubernetes operator provisioning network boundaries — VPCs, TGW, PrivateLink, micro-segmentation
# Detection signals: network-boundary, network_boundary, NetworkBoundary, nbf, netboundary

terraform {
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.0" }
  }
  backend "s3" {
    bucket         = "enterprise-terraform-state-production"
    key            = "factories/network-boundary-factory/terraform.tfstate"
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
      "enterprise-app-id" = "network-boundary-factory"
      "environment"       = var.environment
      "managed-by"        = "terraform"
      "cost-center"       = "CC-PLATFORM-002"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_eks_cluster" "controlplane" { name = var.eks_cluster_name }

# ── IRSA — IAM Role for Service Account (network-boundary-sa) ─────────────────

resource "aws_iam_role" "network_boundary_operator" {
  name                 = "controlplane-network-boundary"
  description          = "IRSA role for network-boundary-factory operator — manages VPC/TGW/PrivateLink lifecycle"
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
          "${replace(data.aws_eks_cluster.controlplane.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:network-boundary-factory:network-boundary-sa"
          "${replace(data.aws_eks_cluster.controlplane.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    "enterprise-app-id" = "network-boundary-factory"
    "factory-type"      = "network-boundary"
    "irsa-sa"           = "network-boundary-sa"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-002"
  }
}

resource "aws_iam_policy" "network_boundary_operator" {
  name        = "network-boundary-factory-policy"
  description = "IAM policy for network-boundary-factory (nbf) operator — VPC/TGW/SG management"
  path        = "/controlplane/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VPCProvisioningFull"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
          "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
          "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway",
          "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
          "ec2:CreateRouteTable", "ec2:DeleteRouteTable",
          "ec2:CreateRoute", "ec2:DeleteRoute",
          "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
          "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateVpcEndpoint", "ec2:DeleteVpcEndpoints",
          "ec2:ModifyVpcEndpoint",
          "ec2:CreateFlowLogs", "ec2:DeleteFlowLogs",
          "ec2:CreateNatGateway", "ec2:DeleteNatGateway",
          "ec2:AllocateAddress", "ec2:ReleaseAddress",
          "ec2:CreateNetworkAcl", "ec2:DeleteNetworkAcl",
          "ec2:CreateNetworkAclEntry", "ec2:DeleteNetworkAclEntry",
          "ec2:Describe*", "ec2:CreateTags", "ec2:DeleteTags",
        ]
        Resource = "*"
      },
      {
        Sid    = "TransitGatewayFull"
        Effect = "Allow"
        Action = [
          "ec2:CreateTransitGateway", "ec2:DeleteTransitGateway",
          "ec2:ModifyTransitGateway",
          "ec2:CreateTransitGatewayVpcAttachment", "ec2:DeleteTransitGatewayVpcAttachment",
          "ec2:ModifyTransitGatewayVpcAttachment",
          "ec2:CreateTransitGatewayRouteTable", "ec2:DeleteTransitGatewayRouteTable",
          "ec2:CreateTransitGatewayRoute", "ec2:DeleteTransitGatewayRoute",
          "ec2:AssociateTransitGatewayRouteTable",
          "ec2:DisassociateTransitGatewayRouteTable",
          "ec2:EnableTransitGatewayRouteTablePropagation",
        ]
        Resource = "*"
      },
      {
        Sid    = "RAMSharing"
        Effect = "Allow"
        Action = [
          "ram:CreateResourceShare", "ram:DeleteResourceShare",
          "ram:UpdateResourceShare", "ram:AssociateResourceShare",
          "ram:DisassociateResourceShare", "ram:GetResourceShareAssociations",
          "ram:GetResourceShares", "ram:AcceptResourceShareInvitation",
        ]
        Resource = "*"
      },
      {
        Sid    = "Route53PrivateDNS"
        Effect = "Allow"
        Action = [
          "route53:CreateHostedZone", "route53:DeleteHostedZone",
          "route53:AssociateVPCWithHostedZone", "route53:DisassociateVPCFromHostedZone",
          "route53:ChangeResourceRecordSets", "route53:ListHostedZones",
          "route53:GetHostedZone", "route53:ListResourceRecordSets",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "network_boundary_operator" {
  role       = aws_iam_role.network_boundary_operator.name
  policy_arn = aws_iam_policy.network_boundary_operator.arn
}

# ── Kubernetes Service Account ────────────────────────────────────────────────

resource "kubernetes_namespace" "network_boundary_factory" {
  metadata {
    name = "network-boundary-factory"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "factory-type"                 = "network-boundary"
      "nbf"                          = "true"
    }
  }
}

resource "kubernetes_service_account" "network_boundary_sa" {
  metadata {
    name      = "network-boundary-sa"
    namespace = kubernetes_namespace.network_boundary_factory.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn"               = aws_iam_role.network_boundary_operator.arn
      "eks.amazonaws.com/token-expiration"       = "86400"
      "eks.amazonaws.com/sts-regional-endpoints" = "true"
    }
    labels = {
      "app.kubernetes.io/name"      = "network-boundary-factory"
      "app.kubernetes.io/component" = "operator"
      "factory-type"                = "network-boundary"
      "netboundary"                 = "true"
    }
  }
}

# ── RBAC ─────────────────────────────────────────────────────────────────────

resource "kubernetes_cluster_role" "network_boundary_operator" {
  metadata {
    name = "network-boundary-operator"
    labels = {
      "factory-type" = "network-boundary"
      "nbf"          = "true"
    }
  }

  rule {
    api_groups = ["enterprise.io"]
    resources  = ["networkboundaries", "vpcboundaries", "networksegments"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["enterprise.io"]
    resources  = ["networkboundaries/status", "vpcboundaries/status"]
    verbs      = ["get", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps", "secrets", "events"]
    verbs      = ["get", "list", "watch", "create", "update"]
  }
}

resource "kubernetes_cluster_role_binding" "network_boundary_operator" {
  metadata {
    name = "network-boundary-operator"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.network_boundary_operator.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.network_boundary_sa.metadata[0].name
    namespace = kubernetes_namespace.network_boundary_factory.metadata[0].name
  }
}

# ── CRD: NetworkBoundary ──────────────────────────────────────────────────────

resource "kubernetes_manifest" "crd_network_boundary" {
  manifest = {
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata = {
      name = "networkboundaries.enterprise.io"
      labels = {
        "factory-type" = "network-boundary-factory"
        "nbf"          = "true"
      }
    }
    spec = {
      group = "enterprise.io"
      names = {
        kind       = "NetworkBoundary"
        listKind   = "NetworkBoundaryList"
        plural     = "networkboundaries"
        singular   = "networkboundary"
        shortNames = ["nbf", "netboundary"]
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
                  accountId       = { type = "string" }
                  region          = { type = "string" }
                  vpcCidr         = { type = "string" }
                  availabilityZones = { type = "array", items = { type = "string" } }
                  transitGatewayId = { type = "string" }
                  enablePrivateLink = { type = "boolean" }
                  flowLogsEnabled   = { type = "boolean" }
                  boundaryType    = { type = "string", enum = ["WORKLOAD", "SHARED", "DMZ", "MANAGEMENT"] }
                  networkSegments = {
                    type = "array"
                    items = {
                      type = "object"
                      properties = {
                        name    = { type = "string" }
                        cidr    = { type = "string" }
                        tier    = { type = "string" }
                        public  = { type = "boolean" }
                      }
                    }
                  }
                }
                required = ["accountId", "region", "vpcCidr", "boundaryType"]
              }
              status = {
                type = "object"
                properties = {
                  phase    = { type = "string" }
                  vpcId    = { type = "string" }
                  subnetIds = { type = "array", items = { type = "string" } }
                  tgwAttachmentId = { type = "string" }
                  lastReconcileTime = { type = "string" }
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

# ── CRD: VPCBoundary ──────────────────────────────────────────────────────────

resource "kubernetes_manifest" "crd_vpc_boundary" {
  manifest = {
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata = {
      name = "vpcboundaries.enterprise.io"
      labels = {
        "factory-type" = "network-boundary-factory"
        "nbf"          = "true"
      }
    }
    spec = {
      group = "enterprise.io"
      names = {
        kind     = "VPCBoundary"
        plural   = "vpcboundaries"
        singular = "vpcboundary"
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
                  networkBoundaryRef = { type = "string" }
                  isolationLevel     = { type = "string", enum = ["FULL", "PARTIAL", "TRUSTED"] }
                  allowedCidrs       = { type = "array", items = { type = "string" } }
                  requirePrivateLink = { type = "boolean" }
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

# ── Outputs ───────────────────────────────────────────────────────────────────

output "network_boundary_role_arn" {
  description = "IRSA IAM role ARN for network-boundary-factory (nbf) operator"
  value       = aws_iam_role.network_boundary_operator.arn
}

output "network_boundary_sa_name" {
  description = "Kubernetes service account name (network-boundary-sa)"
  value       = kubernetes_service_account.network_boundary_sa.metadata[0].name
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region" { type = string; default = "us-east-1" }
variable "environment" { type = string; default = "production" }
variable "eks_cluster_name" { type = string }
variable "permissions_boundary_arn" { type = string }
