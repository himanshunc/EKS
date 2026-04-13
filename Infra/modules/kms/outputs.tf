output "key_arn" {
  description = "ARN of the KMS key — passed to the EKS module for secrets encryption"
  value       = aws_kms_key.eks.arn
}

output "key_id" {
  description = "ID of the KMS key — used when granting additional key permissions"
  value       = aws_kms_key.eks.key_id
}

output "key_alias" {
  description = "Human-readable alias of the KMS key"
  value       = aws_kms_alias.eks.name
}
