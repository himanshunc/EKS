output "state_bucket_name" {
  description = "S3 bucket name — paste this into infra/global/backend.tf as 'bucket'"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "dynamodb_table_name" {
  description = "DynamoDB table name — paste this into infra/global/backend.tf as 'dynamodb_table'"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "aws_region" {
  description = "Region where bootstrap resources were created"
  value       = var.aws_region
}
