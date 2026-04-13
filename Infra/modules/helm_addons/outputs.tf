output "alb_controller_status" {
  description = "Deployment status of the ALB Controller Helm release"
  value       = helm_release.alb_controller.status
}

output "cluster_autoscaler_status" {
  description = "Deployment status of the Cluster Autoscaler Helm release"
  value       = helm_release.cluster_autoscaler.status
}

output "gp3_storage_class_name" {
  description = "Name of the default gp3 StorageClass — use in PVC definitions"
  value       = kubernetes_storage_class.gp3.metadata[0].name
}
