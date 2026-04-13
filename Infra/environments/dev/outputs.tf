# ─── Cluster ──────────────────────────────────────────────────────────────

output "cluster_name" {
  description = "EKS cluster name — use with: aws eks update-kubeconfig --name <value> --region ap-south-1"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint URL"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = module.eks.cluster_version
}

# ─── Networking ───────────────────────────────────────────────────────────

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs — used for nodes and internal ALBs"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs — used for internet-facing ALBs"
  value       = module.vpc.public_subnet_ids
}

# ─── ECR ──────────────────────────────────────────────────────────────────

output "ecr_repository_urls" {
  description = "ECR repository URLs — use these in your CI/CD pipelines to push images"
  value       = module.ecr.repository_urls
}

# ─── Monitoring ───────────────────────────────────────────────────────────

output "grafana_url" {
  description = "Amazon Managed Grafana URL — open in browser to access dashboards"
  value       = module.monitoring.grafana_workspace_endpoint
}

output "amp_endpoint" {
  description = "AMP Prometheus endpoint — used for remote_write configuration"
  value       = module.monitoring.amp_endpoint
}

# ─── Logging ──────────────────────────────────────────────────────────────

output "log_group_name" {
  description = "CloudWatch log group for container logs"
  value       = module.logging.log_group_name
}

# ─── KMS ──────────────────────────────────────────────────────────────────

output "kms_key_arn" {
  description = "KMS key ARN used for EKS secrets encryption"
  value       = module.kms.key_arn
}

# ─── CI/CD ────────────────────────────────────────────────────────────────

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC — add this as the AWS_ROLE_ARN secret in your GitHub repo settings"
  value       = module.iam.github_actions_role_arn
}

output "github_actions_terraform_role_arn" {
  description = "IAM role ARN for Terraform CI — add this as the TF_ROLE_ARN secret in your GitHub repo settings"
  value       = module.iam.github_actions_terraform_role_arn
}
