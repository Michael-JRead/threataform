# layer4-network/tgw.tf
# Layer 4 — Network Boundary: Transit Gateway + RAM sharing
# Detection signals: aws_transit_gateway, aws_ec2_transit_gateway, tgw, transit-gateway

resource "aws_ec2_transit_gateway" "main" {
  description                     = "Enterprise Transit Gateway — hub for all VPC connectivity"
  amazon_side_asn                 = 64512
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  multicast_support               = "disable"

  tags = {
    "Name"              = "enterprise-tgw-prod-001"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
    "transit-gateway"   = "main"
  }
}

# ── TGW Route Tables ──────────────────────────────────────────────────────────

resource "aws_ec2_transit_gateway_route_table" "production" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  tags = {
    "Name"              = "enterprise-tgw-rt-production"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_ec2_transit_gateway_route_table" "management" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  tags = {
    "Name"        = "enterprise-tgw-rt-management"
    "environment" = "management"
    "managed-by"  = "terraform"
    "cost-center" = "CC-NETWORK-004"
  }
}

resource "aws_ec2_transit_gateway_route_table" "shared_services" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  tags = {
    "Name"        = "enterprise-tgw-rt-shared-services"
    "environment" = "production"
    "managed-by"  = "terraform"
    "cost-center" = "CC-NETWORK-004"
  }
}

# ── TGW VPC Attachments ───────────────────────────────────────────────────────

resource "aws_ec2_transit_gateway_vpc_attachment" "production" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.production.id
  subnet_ids         = [aws_subnet.prod_private_a.id, aws_subnet.prod_private_b.id]

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  dns_support                                     = "enable"
  ipv6_support                                    = "disable"
  appliance_mode_support                          = "disable"

  tags = {
    "Name"              = "enterprise-tgw-attach-production"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "management" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.management.id
  subnet_ids         = [aws_subnet.mgmt_private_a.id, aws_subnet.mgmt_private_b.id]

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = {
    "Name"              = "enterprise-tgw-attach-management"
    "enterprise-app-id" = "network-platform"
    "environment"       = "management"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "shared_services" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.shared_services.id
  subnet_ids         = [aws_subnet.shared_private_a.id, aws_subnet.shared_private_b.id]

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = {
    "Name"              = "enterprise-tgw-attach-shared"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

# ── TGW Route Table Associations & Propagations ───────────────────────────────

resource "aws_ec2_transit_gateway_route_table_association" "production" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.production.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
}

resource "aws_ec2_transit_gateway_route_table_association" "management" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.management.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.management.id
}

resource "aws_ec2_transit_gateway_route_table_association" "shared_services" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared_services.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared_services.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "management_to_production" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.management.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "shared_to_production" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared_services.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "production_to_management" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.production.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.management.id
}

# ── TGW Static Routes ─────────────────────────────────────────────────────────

resource "aws_ec2_transit_gateway_route" "blackhole_internet" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
  blackhole                      = true
}

# ── RAM — Share TGW to Organization ──────────────────────────────────────────

resource "aws_ram_resource_share" "tgw" {
  name                      = "enterprise-tgw-org-share"
  allow_external_principals = false

  tags = {
    "Name"              = "enterprise-tgw-org-share"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_ram_resource_association" "tgw" {
  resource_arn       = aws_ec2_transit_gateway.main.arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

resource "aws_ram_principal_association" "tgw_org" {
  principal          = var.organization_arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

# ── VPC Endpoints ─────────────────────────────────────────────────────────────
# HIPAA-05: VPC endpoints for AWS services (no data over public internet)

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.production.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.prod_private_a.id,
    aws_route_table.prod_private_b.id,
    aws_route_table.prod_db.id,
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
      Resource  = ["arn:aws:s3:::*"]
      Condition = {
        StringEquals = { "aws:PrincipalOrgID" = var.organization_id }
      }
    }]
  })

  tags = {
    "Name"              = "enterprise-vpce-s3-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.production.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.prod_private_a.id, aws_route_table.prod_private_b.id]

  tags = {
    "Name"              = "enterprise-vpce-dynamodb-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "enterprise-sg-vpc-endpoints"
  description = "Security group for Interface VPC endpoints — HTTPS only from private subnets"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.production.cidr_block]
    description = "HTTPS from VPC for VPC endpoint access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all egress"
  }

  tags = {
    "Name"              = "enterprise-sg-vpc-endpoints"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.production.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.prod_private_a.id, aws_subnet.prod_private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    "Name"              = "enterprise-vpce-secretsmanager-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.production.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.prod_private_a.id, aws_subnet.prod_private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    "Name"              = "enterprise-vpce-ssm-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.production.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.prod_private_a.id, aws_subnet.prod_private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    "Name"              = "enterprise-vpce-ec2messages-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_vpc_endpoint" "kms" {
  vpc_id              = aws_vpc.production.id
  service_name        = "com.amazonaws.${var.aws_region}.kms"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.prod_private_a.id, aws_subnet.prod_private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    "Name"              = "enterprise-vpce-kms-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.production.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.prod_private_a.id, aws_subnet.prod_private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    "Name"              = "enterprise-vpce-ecr-api-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.production.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.prod_private_a.id, aws_subnet.prod_private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    "Name"              = "enterprise-vpce-ecr-dkr-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.production.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.prod_private_a.id, aws_subnet.prod_private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    "Name"              = "enterprise-vpce-logs-prod"
    "enterprise-app-id" = "network-platform"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-NETWORK-004"
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "transit_gateway_id" {
  value = aws_ec2_transit_gateway.main.id
}

output "tgw_production_rt_id" {
  value = aws_ec2_transit_gateway_route_table.production.id
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region" { type = string; default = "us-east-1" }
variable "environment" { type = string; default = "production" }
variable "organization_id" { type = string }
variable "organization_arn" { type = string }
variable "kms_key_arn" { type = string }
variable "permissions_boundary_arn" { type = string }
