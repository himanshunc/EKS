locals {
  # KMS key alias — human-readable name shown in AWS Console
  key_alias = "alias/${var.project_name}-${var.environment}-eks"
}
