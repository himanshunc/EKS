output "alb_controller_role_arn" {
  description = "IRSA role ARN for ALB Controller - annotated on the alb-controller service account"
  value       = aws_iam_role.alb_controller.arn
}

output "cluster_autoscaler_role_arn" {
  description = "IRSA role ARN for Cluster Autoscaler - annotated on the cluster-autoscaler service account"
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "ebs_csi_driver_role_arn" {
  description = "IRSA role ARN for EBS CSI Driver - annotated on the ebs-csi-controller-sa service account"
  value       = aws_iam_role.ebs_csi_driver.arn
}

output "amp_ingest_role_arn" {
  description = "IRSA role ARN for Prometheus agent - annotated on the prometheus-agent service account"
  value       = aws_iam_role.amp_ingest.arn
}

output "grafana_role_arn" {
  description = "IRSA role ARN for Grafana OSS - annotated on the grafana service account in monitoring namespace"
  value       = aws_iam_role.grafana.arn
}

output "amg_role_arn" {
  description = "IAM role ARN for AMG workspace - passed to the monitoring module"
  value       = aws_iam_role.amg.arn
}
