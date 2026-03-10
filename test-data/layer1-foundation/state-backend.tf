# layer1-foundation/state-backend.tf
# Layer 1 — Foundation: Terraform state backend (S3 + DynamoDB lock)
# SOX-03: DynamoDB lock prevents concurrent state changes
# SOX-04: S3 versioning for state integrity

# ── KMS key for state encryption ─────────────────────────────────────────────

resource "aws_kms_key" "tfstate" {
  description             = "KMS CMK for Terraform state file encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  multi_region            = false

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM permissions"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.management_account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow S3 service"
        Effect = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = "*"
      }
    ]
  })

  tags = {
    "enterprise-app-id"   = "bootstrap-001"
    "environment"         = "management"
    "managed-by"          = "terraform"
    "cost-center"         = "CC-PLATFORM-001"
    "data-classification" = "confidential"
  }
}

resource "aws_kms_alias" "tfstate" {
  name          = "alias/enterprise-tfstate-key"
  target_key_id = aws_kms_key.tfstate.key_id
}

# ── S3 state buckets (per environment) ───────────────────────────────────────

resource "aws_s3_bucket" "tfstate_management" {
  bucket        = "enterprise-terraform-state-bootstrap"
  force_destroy = false

  tags = {
    "enterprise-app-id"   = "bootstrap-001"
    "environment"         = "management"
    "managed-by"          = "terraform"
    "cost-center"         = "CC-PLATFORM-001"
    "data-classification" = "confidential"
  }
}

resource "aws_s3_bucket_versioning" "tfstate_management" {
  bucket = aws_s3_bucket.tfstate_management.id
  versioning_configuration {
    status = "Enabled"   # SOX-04 — required for state integrity
    mfa_delete = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate_management" {
  bucket = aws_s3_bucket.tfstate_management.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tfstate.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate_management" {
  bucket                  = aws_s3_bucket.tfstate_management.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "tfstate_management" {
  bucket        = aws_s3_bucket.tfstate_management.id
  target_bucket = aws_s3_bucket.tfstate_management.id
  target_prefix = "state-access-logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate_management" {
  bucket = aws_s3_bucket.tfstate_management.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Production state bucket
resource "aws_s3_bucket" "tfstate_production" {
  bucket        = "enterprise-terraform-state-production"
  force_destroy = false

  tags = {
    "enterprise-app-id"   = "bootstrap-001"
    "environment"         = "production"
    "managed-by"          = "terraform"
    "cost-center"         = "CC-PLATFORM-001"
    "data-classification" = "confidential"
  }
}

resource "aws_s3_bucket_versioning" "tfstate_production" {
  bucket = aws_s3_bucket.tfstate_production.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate_production" {
  bucket = aws_s3_bucket.tfstate_production.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tfstate.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate_production" {
  bucket                  = aws_s3_bucket.tfstate_production.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Non-prod state bucket
resource "aws_s3_bucket" "tfstate_nonprod" {
  bucket        = "enterprise-terraform-state-nonprod"
  force_destroy = false

  tags = {
    "enterprise-app-id" = "bootstrap-001"
    "environment"       = "staging"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-001"
  }
}

resource "aws_s3_bucket_versioning" "tfstate_nonprod" {
  bucket = aws_s3_bucket.tfstate_nonprod.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "tfstate_nonprod" {
  bucket                  = aws_s3_bucket.tfstate_nonprod.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── DynamoDB lock tables — SOX-03 ─────────────────────────────────────────────

resource "aws_dynamodb_table" "terraform_state_lock" {
  name           = "terraform-state-lock"   # LockID attribute — SOX-03 detection
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.tfstate.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    "enterprise-app-id"   = "bootstrap-001"
    "environment"         = "management"
    "managed-by"          = "terraform"
    "cost-center"         = "CC-PLATFORM-001"
    "data-classification" = "internal"
  }
}

resource "aws_dynamodb_table" "terraform_state_lock_prod" {
  name         = "terraform-state-lock-production"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.tfstate.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    "enterprise-app-id" = "bootstrap-001"
    "environment"       = "production"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-001"
  }
}

resource "aws_dynamodb_table" "terraform_state_lock_nonprod" {
  name         = "terraform-state-lock-nonprod"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    "enterprise-app-id" = "bootstrap-001"
    "environment"       = "staging"
    "managed-by"        = "terraform"
    "cost-center"       = "CC-PLATFORM-001"
  }
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "management_account_id" {
  type        = string
  description = "AWS Management account ID"
}
