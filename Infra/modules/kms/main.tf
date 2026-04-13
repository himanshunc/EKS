# ─────────────────────────────────────────────────────────────────────────────
# KMS Module — Step 1
# Creates a customer-managed KMS key used to encrypt EKS secrets at rest.
# Key rotation is mandatory — AWS rotates key material annually, automatically.
# ─────────────────────────────────────────────────────────────────────────────

# Fetch the current AWS account ID — needed to build the key policy
data "aws_caller_identity" "current" {}

# KMS Key — encrypts EKS Kubernetes Secrets (etcd at rest).
# Without this, secrets (like service account tokens) are stored in plaintext in etcd.
resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS secrets encryption - ${var.project_name}-${var.environment}"
  deletion_window_in_days = 7                # minimum AWS allows; change to 30 for prod
  enable_key_rotation     = true             # rotates key material annually — MANDATORY security practice
  multi_region            = false            # single-region is sufficient for one EKS cluster

  # Key policy — grants this account root access so IAM can delegate from here.
  # Without a key policy, no IAM role (including cluster role) can use the key.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

# KMS Alias — human-readable name for the key in the AWS Console.
# EKS references the alias so you can rotate the underlying key without changing config.
resource "aws_kms_alias" "eks" {
  name          = local.key_alias
  target_key_id = aws_kms_key.eks.key_id
}
