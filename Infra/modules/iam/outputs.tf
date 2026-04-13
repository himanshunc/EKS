output "cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role - passed to the eks module"
  value       = aws_iam_role.eks_cluster.arn
}

output "node_role_arn" {
  description = "ARN of the EKS node IAM role - passed to the node_groups module"
  value       = aws_iam_role.eks_node.arn
}

output "node_role_name" {
  description = "Name of the EKS node IAM role - used to attach additional policies if needed"
  value       = aws_iam_role.eks_node.name
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions OIDC — set this as the AWS_ROLE_ARN secret in your GitHub repo"
  value       = aws_iam_role.github_actions.arn
}
