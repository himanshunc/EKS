# ─────────────────────────────────────────────────────────────────────────────
# Bootstrap — Step 0
# Run ONCE before any other Terraform.
# Creates the S3 bucket (state storage) and DynamoDB table (state locking).
# After applying, copy the outputs into infra/global/backend.tf.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # Unique suffix using account ID prevents bucket name collisions across accounts
  bucket_name = "${var.project_name}-terraform-state-${data.aws_caller_identity.current.account_id}"
  table_name  = "${var.project_name}-terraform-locks"
}

# Fetch the current AWS account ID — used to make the S3 bucket name unique
data "aws_caller_identity" "current" {}

# ─── S3 Bucket — Terraform remote state storage ───────────────────────────

# S3 bucket to store all Terraform state files.
# versioning = true so you can roll back to any previous state.
resource "aws_s3_bucket" "terraform_state" {
  bucket = local.bucket_name

  # Prevent accidental deletion of the state bucket
  lifecycle {
    prevent_destroy = true
  }
}

# Enable versioning — keeps every version of every state file.
# Essential for disaster recovery: you can restore any previous state.
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption — state files contain sensitive data.
# AES256 is the AWS-managed default; use aws:kms for stricter compliance.
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access — state files must never be public.
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── DynamoDB Table — Terraform state locking ─────────────────────────────

# DynamoDB table for state locking.
# Prevents two engineers (or two CI runs) from applying at the same time,
# which would corrupt the state file.
resource "aws_dynamodb_table" "terraform_locks" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST" # no capacity planning needed — low traffic table
  hash_key     = "LockID"          # Terraform always uses "LockID" as the key

  attribute {
    name = "LockID"
    type = "S" # String
  }
}
