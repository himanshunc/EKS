output "cluster_name" {
  description = "EKS cluster name — used by providers, helm releases, and IRSA conditions"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint — used to configure the Kubernetes and Helm providers"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate — used to configure the Kubernetes and Helm providers"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = aws_eks_cluster.this.version
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider — used in IRSA trust policies in the iam module"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider" {
  description = "Hostname of the OIDC provider (without https://) — used in IRSA trust policy conditions"
  value       = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}
