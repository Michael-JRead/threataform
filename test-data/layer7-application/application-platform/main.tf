# layer7-application/application-platform/main.tf
# Layer 7 — Application Layer: application-platform (EKS + SSO + API GW)
# Detection signals: application-*, app*.tf, custom-*.tf

terraform {
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.0" }
    helm       = { source = "hashicorp/helm", version = "~> 2.0" }
  }
  backend "s3" {
    bucket         = "enterprise-terraform-state-production"
    key            = "applications/application-platform/terraform.tfstate"
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
      "enterprise-app-id" = "application-platform"
      "environment"       = var.environment
      "managed-by"        = "terraform"
      "cost-center"       = "CC-PLATFORM-007"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ── KMS key for EKS ──────────────────────────────────────────────────────────

resource "aws_kms_key" "eks" {
  description             = "KMS CMK for EKS secrets encryption — application-platform"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    "enterprise-app-id" = "application-platform"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-007"
    "kubernetes"        = "eks"
    "container"         = "true"
  }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/enterprise-eks-${var.cluster_name}"
  target_key_id = aws_kms_key.eks.key_id
}

# ── IAM Roles for EKS ────────────────────────────────────────────────────────

resource "aws_iam_role" "eks_cluster" {
  name                 = "enterprise-eks-cluster-${var.cluster_name}"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    "enterprise-app-id" = "application-platform"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-007"
    "kubernetes"        = "cluster"
    "eks"               = "control-plane"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_iam_role" "eks_node_group" {
  name                 = "enterprise-eks-nodegroup-${var.cluster_name}"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    "enterprise-app-id" = "application-platform"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-007"
    "kubernetes"        = "node-group"
    "fargate"           = "optional"
  }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  role       = aws_iam_role.eks_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_readonly" {
  role       = aws_iam_role.eks_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_ssm" {
  role       = aws_iam_role.eks_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "enterprise" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = var.enable_public_endpoint
    public_access_cidrs     = var.enable_public_endpoint ? var.public_endpoint_cidrs : []
    security_group_ids      = [var.eks_control_plane_sg_id]
  }

  # Secrets encryption with KMS
  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = [
    "api", "audit", "authenticator", "controllerManager", "scheduler"
  ]

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = false
  }

  tags = {
    "enterprise-app-id" = "application-platform"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-007"
    "kubernetes"        = "eks"
    "eks"               = "cluster"
    "container"         = "true"
    "docker"            = "kubernetes"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]
}

# EKS OIDC Provider (for IRSA)
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.enterprise.identity[0].oidc[0].issuer

  tags = {
    "enterprise-app-id" = "application-platform"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-007"
    "kubernetes"        = "irsa-oidc"
  }
}

data "tls_certificate" "eks" {
  url = aws_eks_cluster.enterprise.identity[0].oidc[0].issuer
}

# ── EKS Node Group ────────────────────────────────────────────────────────────

resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.enterprise.name
  node_group_name = "${var.cluster_name}-system-nodes"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = var.private_subnet_ids

  ami_type       = "BOTTLEROCKET_ARM_64"
  instance_types = var.node_instance_types
  capacity_type  = "ON_DEMAND"
  disk_size      = 100

  scaling_config {
    desired_size = var.node_desired_count
    max_size     = var.node_max_count
    min_size     = var.node_min_count
  }

  update_config {
    max_unavailable_percentage = 25
  }

  labels = {
    "role"                        = "system"
    "node-type"                   = "managed"
    "enterprise-app-id"           = "application-platform"
    "kubernetes.io/os"            = "linux"
    "eks.amazonaws.com/nodegroup" = "${var.cluster_name}-system-nodes"
  }

  taint {
    key    = "dedicated"
    value  = "system"
    effect = "NO_SCHEDULE"
  }

  # Launch template for IMDSv2 enforcement
  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  tags = {
    "enterprise-app-id" = "application-platform"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-007"
    "kubernetes"        = "node-group"
    "fargate"           = "false"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.eks_ecr_readonly,
    aws_iam_role_policy_attachment.eks_ssm,
  ]
}

# Launch template enforces IMDSv2 on all nodes
resource "aws_launch_template" "eks_nodes" {
  name_prefix = "enterprise-eks-${var.cluster_name}-"
  description = "application-platform: EKS node launch template — IMDSv2 enforced"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 — PCI-07
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 100
      encrypted             = true
      kms_key_id            = aws_kms_key.eks.arn
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      "enterprise-app-id" = "application-platform"
      "environment"       = var.environment
      "managed-by"        = "terraform"
      "cost-center"       = "CC-PLATFORM-007"
      "kubernetes"        = "node"
    }
  }

  tags = {
    "enterprise-app-id" = "application-platform"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-007"
  }
}

# ── Fargate Profile ───────────────────────────────────────────────────────────

resource "aws_iam_role" "fargate_pod_execution" {
  name                 = "enterprise-eks-fargate-${var.cluster_name}"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks-fargate-pods.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    "enterprise-app-id" = "application-platform"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-007"
    "kubernetes"        = "fargate"
    "fargate"           = "pod-execution"
  }
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution" {
  role       = aws_iam_role.fargate_pod_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

resource "aws_eks_fargate_profile" "kube_system" {
  cluster_name           = aws_eks_cluster.enterprise.name
  fargate_profile_name   = "kube-system"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = "kube-system"
    labels    = { "eks.amazonaws.com/component" = "coredns" }
  }

  tags = {
    "enterprise-app-id" = "application-platform"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-007"
    "kubernetes"        = "fargate-profile"
    "fargate"           = "true"
    "container"         = "kubernetes"
  }
}

# ── API Gateway ───────────────────────────────────────────────────────────────

resource "aws_api_gateway_rest_api" "enterprise" {
  name        = "enterprise-${var.cluster_name}-api"
  description = "application-platform: Enterprise REST API gateway for ${var.cluster_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  minimum_compression_size = 1024

  body = jsonencode({
    openapi = "3.0.1"
    info = {
      title   = "Enterprise API"
      version = "1.0"
    }
    paths = {
      "/health" = {
        get = {
          responses = { "200" = { description = "Health check" } }
          "x-amazon-apigateway-integration" = {
            type = "MOCK"
            requestTemplates = { "application/json" = "{\"statusCode\": 200}" }
            responses = { default = { statusCode = "200" } }
          }
        }
      }
    }
  })

  tags = {
    "enterprise-app-id" = "application-platform"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-007"
    "api_gateway"       = "true"
    "apigw"             = "rest-api"
    "rest_api"          = "enterprise"
    "graphql"           = "false"
  }
}

resource "aws_api_gateway_deployment" "enterprise" {
  rest_api_id = aws_api_gateway_rest_api.enterprise.id
  depends_on  = [aws_api_gateway_rest_api.enterprise]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.enterprise.id
  rest_api_id   = aws_api_gateway_rest_api.enterprise.id
  stage_name    = var.environment

  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
  }

  default_route_settings {
    logging_level          = "INFO"
    data_trace_enabled     = false
    metrics_enabled        = true
    throttling_burst_limit = 1000
    throttling_rate_limit  = 500
  }

  tags = {
    "enterprise-app-id" = "application-platform"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-007"
    "apigw"             = "stage"
  }
}

resource "aws_api_gateway_usage_plan" "enterprise" {
  name        = "enterprise-${var.cluster_name}-usage-plan"
  description = "application-platform: API usage plan with throttling"

  api_stages {
    api_id = aws_api_gateway_rest_api.enterprise.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  quota_settings {
    limit  = 1000000
    period = "MONTH"
  }

  throttle_settings {
    burst_limit = 1000
    rate_limit  = 500
  }

  tags = {
    "enterprise-app-id" = "application-platform"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-007"
  }
}

# ── SSO Permission Sets for application teams ─────────────────────────────────

data "aws_ssoadmin_instances" "primary" {}

resource "aws_ssoadmin_permission_set" "developer" {
  name             = "enterprise-developer-${var.cluster_name}"
  description      = "application-platform: Developer read/deploy access via SSO"
  instance_arn     = tolist(data.aws_ssoadmin_instances.primary.arns)[0]
  session_duration = "PT8H"

  relay_state = "https://console.aws.amazon.com/ecs/home"

  tags = {
    "enterprise-app-id" = "application-platform"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-007"
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "developer_readonly" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.primary.arns)[0]
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn
}

resource "aws_ssoadmin_permission_set" "platform_admin" {
  name             = "enterprise-platform-admin-${var.cluster_name}"
  description      = "application-platform: Platform admin full access via SSO"
  instance_arn     = tolist(data.aws_ssoadmin_instances.primary.arns)[0]
  session_duration = "PT4H"

  tags = {
    "enterprise-app-id" = "application-platform"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-007"
  }
}

# ── Monitoring ────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/enterprise/apigateway/${var.cluster_name}"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.eks.arn
  tags = { "enterprise-app-id" = "application-platform", "environment" = var.environment, "managed-by" = "terraform", "cost-center" = "CC-PLATFORM-007" }
}

resource "aws_cloudwatch_log_group" "eks_audit" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.eks.arn
  tags = { "enterprise-app-id" = "application-platform", "environment" = var.environment, "managed-by" = "terraform", "cost-center" = "CC-PLATFORM-007" }
}

resource "aws_cloudwatch_metric_alarm" "eks_nodes_not_ready" {
  alarm_name          = "enterprise-eks-${var.cluster_name}-nodes-not-ready"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "node_status_condition"
  namespace           = "ContainerInsights"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "application-platform: EKS nodes in NotReady state"
  alarm_actions       = [var.sns_alert_arn]
  dimensions = { ClusterName = aws_eks_cluster.enterprise.name, NodeGroupName = aws_eks_node_group.system.node_group_name }
  tags = { "enterprise-app-id" = "application-platform", "environment" = var.environment, "managed-by" = "terraform", "cost-center" = "CC-PLATFORM-007" }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "eks_cluster_endpoint"        { value = aws_eks_cluster.enterprise.endpoint; sensitive = true }
output "eks_cluster_ca"              { value = aws_eks_cluster.enterprise.certificate_authority[0].data; sensitive = true }
output "eks_cluster_name"            { value = aws_eks_cluster.enterprise.name }
output "eks_oidc_provider_arn"       { value = aws_iam_openid_connect_provider.eks.arn }
output "eks_oidc_provider_url"       { value = aws_eks_cluster.enterprise.identity[0].oidc[0].issuer }
output "api_gateway_invoke_url"      { value = aws_api_gateway_stage.prod.invoke_url; sensitive = true }
output "api_gateway_id"              { value = aws_api_gateway_rest_api.enterprise.id }
output "kms_key_arn"                 { value = aws_kms_key.eks.arn }

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region"               { type = string; default = "us-east-1" }
variable "environment"              { type = string; default = "production" }
variable "cluster_name"             { type = string }
variable "kubernetes_version"       { type = string; default = "1.29" }
variable "node_instance_types"      { type = list(string); default = ["m6i.xlarge"] }
variable "node_desired_count"       { type = number; default = 3 }
variable "node_min_count"           { type = number; default = 3 }
variable "node_max_count"           { type = number; default = 20 }
variable "enable_public_endpoint"   { type = bool;   default = false }
variable "public_endpoint_cidrs"    { type = list(string); default = [] }
variable "vpc_id"                   { type = string }
variable "private_subnet_ids"      { type = list(string) }
variable "public_subnet_ids"       { type = list(string) }
variable "eks_control_plane_sg_id"  { type = string }
variable "sns_alert_arn"            { type = string }
variable "permissions_boundary_arn" { type = string }
