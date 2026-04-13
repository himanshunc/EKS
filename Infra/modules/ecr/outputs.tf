output "repository_urls" {
  description = "Map of repository name → ECR URL — use these in your CI/CD pipelines to push images"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "Map of repository name → ECR ARN — used in IAM policies to restrict image push/pull access"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}
