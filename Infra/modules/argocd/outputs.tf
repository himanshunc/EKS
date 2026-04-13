output "argocd_release_status" {
  description = "Helm release status of ArgoCD deployment"
  value       = helm_release.argocd.status
}

output "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD is deployed"
  value       = helm_release.argocd.namespace
}

output "argocd_version" {
  description = "Deployed version of the ArgoCD Helm chart"
  value       = helm_release.argocd.version
}
