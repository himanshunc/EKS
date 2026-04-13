output "log_group_name" {
  description = "CloudWatch log group name — use this in CloudWatch queries or AMG log explorer"
  value       = aws_cloudwatch_log_group.containers.name
}

output "log_group_arn" {
  description = "CloudWatch log group ARN — used in IAM policies to grant read access"
  value       = aws_cloudwatch_log_group.containers.arn
}

output "fluent_bit_release_status" {
  description = "Helm release status of FluentBit"
  value       = helm_release.fluent_bit.status
}
