# layer4-network/vpc.tf
# Layer 4 — Network Boundary: VPCs, subnets, TGW, VPC endpoints, flow logs
# Detection signals: aws_vpc, aws_subnet, aws_transit_gateway, aws_flow_log, aws_vpc_endpoint
# Naming: enterprise-vpc-prod-001, enterprise-vpc-mgmt-001

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "enterprise-terraform-state-production"
    key            = "network/vpc/terraform.tfstate"
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
      "enterprise-app-id" = "network-platform"
      "environment"       = var.environment
      "managed-by"        = "terraform"
      "cost-center"       = "CC-NETWORK-004"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Production Workload VPC ───────────────────────────────────────────────────

resource "aws_vpc" "production" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  instance_tenancy     = "default"

  tags = {
    "Name"              = "enterprise-vpc-prod-001"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
    "network-boundary"  = "workload"
    "tier"              = "production"
  }
}

# Production subnets — private (app tier)
resource "aws_subnet" "prod_private_a" {
  vpc_id                  = aws_vpc.production.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = {
    "Name"              = "enterprise-subnet-prod-private-a"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
    "Tier"              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "prod_private_b" {
  vpc_id                  = aws_vpc.production.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = false

  tags = {
    "Name"        = "enterprise-subnet-prod-private-b"
    "Tier"        = "private"
    "environment" = "production"
    "managed-by"  = "terraform"
    "cost-center" = "CC-NETWORK-004"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "prod_private_c" {
  vpc_id                  = aws_vpc.production.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "${var.aws_region}c"
  map_public_ip_on_launch = false

  tags = {
    "Name"        = "enterprise-subnet-prod-private-c"
    "Tier"        = "private"
    "environment" = "production"
    "managed-by"  = "terraform"
    "cost-center" = "CC-NETWORK-004"
  }
}

# Production subnets — database tier
resource "aws_subnet" "prod_db_a" {
  vpc_id                  = aws_vpc.production.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = {
    "Name"        = "enterprise-subnet-prod-db-a"
    "Tier"        = "database"
    "environment" = "production"
    "managed-by"  = "terraform"
    "cost-center" = "CC-NETWORK-004"
  }
}

resource "aws_subnet" "prod_db_b" {
  vpc_id                  = aws_vpc.production.id
  cidr_block              = "10.0.5.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = false

  tags = {
    "Name"        = "enterprise-subnet-prod-db-b"
    "Tier"        = "database"
    "environment" = "production"
    "managed-by"  = "terraform"
    "cost-center" = "CC-NETWORK-004"
  }
}

# Production subnets — public (ALB/NAT)
resource "aws_subnet" "prod_public_a" {
  vpc_id                  = aws_vpc.production.id
  cidr_block              = "10.0.11.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = {
    "Name"        = "enterprise-subnet-prod-public-a"
    "Tier"        = "public"
    "environment" = "production"
    "managed-by"  = "terraform"
    "cost-center" = "CC-NETWORK-004"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "prod_public_b" {
  vpc_id                  = aws_vpc.production.id
  cidr_block              = "10.0.12.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = false

  tags = {
    "Name"        = "enterprise-subnet-prod-public-b"
    "Tier"        = "public"
    "environment" = "production"
    "managed-by"  = "terraform"
    "cost-center" = "CC-NETWORK-004"
  }
}

# ── Management VPC ────────────────────────────────────────────────────────────

resource "aws_vpc" "management" {
  cidr_block           = "10.100.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    "Name"              = "enterprise-vpc-mgmt-001"
    "enterprise-app-id" = "network-platform"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
    "network-boundary"  = "management"
  }
}

resource "aws_subnet" "mgmt_private_a" {
  vpc_id            = aws_vpc.management.id
  cidr_block        = "10.100.1.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    "Name"        = "enterprise-subnet-mgmt-private-a"
    "Tier"        = "management"
    "environment" = "management"
    "managed-by"  = "terraform"
    "cost-center" = "CC-NETWORK-004"
  }
}

resource "aws_subnet" "mgmt_private_b" {
  vpc_id            = aws_vpc.management.id
  cidr_block        = "10.100.2.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    "Name"        = "enterprise-subnet-mgmt-private-b"
    "Tier"        = "management"
    "environment" = "management"
    "managed-by"  = "terraform"
    "cost-center" = "CC-NETWORK-004"
  }
}

# ── Shared Services VPC ───────────────────────────────────────────────────────

resource "aws_vpc" "shared_services" {
  cidr_block           = "10.200.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    "Name"              = "enterprise-vpc-shared-001"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
    "network-boundary"  = "shared-services"
  }
}

resource "aws_subnet" "shared_private_a" {
  vpc_id            = aws_vpc.shared_services.id
  cidr_block        = "10.200.1.0/24"
  availability_zone = "${var.aws_region}a"
  tags = { "Name" = "enterprise-subnet-shared-private-a", "Tier" = "private", "managed-by" = "terraform", "cost-center" = "CC-NETWORK-004" }
}

resource "aws_subnet" "shared_private_b" {
  vpc_id            = aws_vpc.shared_services.id
  cidr_block        = "10.200.2.0/24"
  availability_zone = "${var.aws_region}b"
  tags = { "Name" = "enterprise-subnet-shared-private-b", "Tier" = "private", "managed-by" = "terraform", "cost-center" = "CC-NETWORK-004" }
}

# ── DB Subnet Groups ──────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "production" {
  name        = "enterprise-db-subnet-group-prod"
  description = "Production database subnet group — private subnets only"
  subnet_ids  = [aws_subnet.prod_db_a.id, aws_subnet.prod_db_b.id]

  tags = {
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_elasticache_subnet_group" "production" {
  name        = "enterprise-cache-subnet-group-prod"
  description = "Production ElastiCache subnet group"
  subnet_ids  = [aws_subnet.prod_private_a.id, aws_subnet.prod_private_b.id]

  tags = {
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────

resource "aws_internet_gateway" "production" {
  vpc_id = aws_vpc.production.id

  tags = {
    "Name"              = "enterprise-igw-prod-001"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

# ── NAT Gateways (HA across AZs) ─────────────────────────────────────────────

resource "aws_eip" "nat_a" {
  domain = "vpc"
  tags = { "Name" = "enterprise-eip-nat-a", "managed-by" = "terraform", "cost-center" = "CC-NETWORK-004" }
}

resource "aws_eip" "nat_b" {
  domain = "vpc"
  tags = { "Name" = "enterprise-eip-nat-b", "managed-by" = "terraform", "cost-center" = "CC-NETWORK-004" }
}

resource "aws_nat_gateway" "prod_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.prod_public_a.id
  depends_on    = [aws_internet_gateway.production]

  tags = {
    "Name"              = "enterprise-nat-prod-a"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_nat_gateway" "prod_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.prod_public_b.id
  depends_on    = [aws_internet_gateway.production]

  tags = {
    "Name"              = "enterprise-nat-prod-b"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

# ── Route Tables ──────────────────────────────────────────────────────────────

resource "aws_route_table" "prod_public" {
  vpc_id = aws_vpc.production.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.production.id
  }

  route {
    cidr_block         = "10.0.0.0/8"
    transit_gateway_id = aws_ec2_transit_gateway.main.id
  }

  tags = {
    "Name"              = "enterprise-rt-prod-public"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_route_table" "prod_private_a" {
  vpc_id = aws_vpc.production.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.prod_a.id
  }

  route {
    cidr_block         = "10.0.0.0/8"
    transit_gateway_id = aws_ec2_transit_gateway.main.id
  }

  tags = {
    "Name"              = "enterprise-rt-prod-private-a"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_route_table" "prod_private_b" {
  vpc_id = aws_vpc.production.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.prod_b.id
  }

  route {
    cidr_block         = "10.0.0.0/8"
    transit_gateway_id = aws_ec2_transit_gateway.main.id
  }

  tags = {
    "Name"              = "enterprise-rt-prod-private-b"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_route_table" "prod_db" {
  vpc_id = aws_vpc.production.id

  # Database subnet: no internet, only TGW and VPC endpoints
  route {
    cidr_block         = "10.0.0.0/8"
    transit_gateway_id = aws_ec2_transit_gateway.main.id
  }

  tags = {
    "Name"              = "enterprise-rt-prod-db"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

# Route table associations
resource "aws_route_table_association" "prod_public_a" {
  subnet_id      = aws_subnet.prod_public_a.id
  route_table_id = aws_route_table.prod_public.id
}

resource "aws_route_table_association" "prod_public_b" {
  subnet_id      = aws_subnet.prod_public_b.id
  route_table_id = aws_route_table.prod_public.id
}

resource "aws_route_table_association" "prod_private_a" {
  subnet_id      = aws_subnet.prod_private_a.id
  route_table_id = aws_route_table.prod_private_a.id
}

resource "aws_route_table_association" "prod_private_b" {
  subnet_id      = aws_subnet.prod_private_b.id
  route_table_id = aws_route_table.prod_private_b.id
}

resource "aws_route_table_association" "prod_private_c" {
  subnet_id      = aws_subnet.prod_private_c.id
  route_table_id = aws_route_table.prod_private_a.id
}

resource "aws_route_table_association" "prod_db_a" {
  subnet_id      = aws_subnet.prod_db_a.id
  route_table_id = aws_route_table.prod_db.id
}

resource "aws_route_table_association" "prod_db_b" {
  subnet_id      = aws_subnet.prod_db_b.id
  route_table_id = aws_route_table.prod_db.id
}

# ── VPC Flow Logs ─────────────────────────────────────────────────────────────
# PCI-04: VPC flow logs for all CDE traffic

resource "aws_flow_log" "production" {
  vpc_id          = aws_vpc.production.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn

  tags = {
    "Name"              = "enterprise-flow-log-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_flow_log" "management" {
  vpc_id          = aws_vpc.management.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn

  tags = {
    "Name"              = "enterprise-flow-log-mgmt"
    "enterprise-app-id" = "network-platform"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_flow_log" "shared_services" {
  vpc_id          = aws_vpc.shared_services.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn

  tags = {
    "Name"              = "enterprise-flow-log-shared"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/enterprise/network/vpc-flow-logs"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = {
    "enterprise-app-id" = "network-platform"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_iam_role" "flow_logs" {
  name = "enterprise-vpc-flow-logs-role"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    "enterprise-app-id" = "network-platform"
    "environment"       = var.environment
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "flow-logs-cloudwatch-policy"
  role = aws_iam_role.flow_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup", "logs:CreateLogStream",
        "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

# ── Network ACLs ──────────────────────────────────────────────────────────────

resource "aws_network_acl" "prod_database" {
  vpc_id     = aws_vpc.production.id
  subnet_ids = [aws_subnet.prod_db_a.id, aws_subnet.prod_db_b.id]

  # Allow PostgreSQL from private subnets only
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "10.0.1.0/24"
    from_port  = 5432
    to_port    = 5432
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "10.0.2.0/24"
    from_port  = 5432
    to_port    = 5432
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "10.0.3.0/24"
    from_port  = 5432
    to_port    = 5432
  }

  # Allow ephemeral return traffic
  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "10.0.0.0/16"
    from_port  = 1024
    to_port    = 65535
  }

  # Deny all other inbound
  ingress {
    protocol   = "-1"
    rule_no    = 32766
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "10.0.0.0/16"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    protocol   = "-1"
    rule_no    = 32766
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    "Name"              = "enterprise-nacl-prod-database"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "prod_vpc_id" {
  value = aws_vpc.production.id
}

output "prod_private_subnet_ids" {
  value = [
    aws_subnet.prod_private_a.id,
    aws_subnet.prod_private_b.id,
    aws_subnet.prod_private_c.id,
  ]
}

output "prod_db_subnet_ids" {
  value = [aws_subnet.prod_db_a.id, aws_subnet.prod_db_b.id]
}

output "prod_public_subnet_ids" {
  value = [aws_subnet.prod_public_a.id, aws_subnet.prod_public_b.id]
}

output "mgmt_vpc_id" {
  value = aws_vpc.management.id
}

output "shared_services_vpc_id" {
  value = aws_vpc.shared_services.id
}

output "db_subnet_group_name" {
  value = aws_db_subnet_group.production.name
}

output "cache_subnet_group_name" {
  value = aws_elasticache_subnet_group.production.name
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region" { type = string; default = "us-east-1" }
variable "environment" { type = string; default = "production" }
variable "kms_key_arn" { type = string }
variable "permissions_boundary_arn" { type = string }
