output "amp_workspace_id" {
  description = "AMP workspace ID - useful for constructing the remote_write URL manually"
  value       = aws_prometheus_workspace.this.id
}

output "amp_endpoint" {
  description = "AMP Prometheus endpoint URL - used by Prometheus agent for remote_write"
  value       = aws_prometheus_workspace.this.prometheus_endpoint
}

output "grafana_access_command" {
  description = "kubectl port-forward command to open Grafana in your browser (admin / admin123)"
  value       = "kubectl port-forward svc/grafana 3000:80 -n monitoring"
}

output "grafana_workspace_id" {
  description = "AMG workspace ID (empty string when enable_amg = false)"
  value       = var.enable_amg ? aws_grafana_workspace.this[0].id : ""
}

output "grafana_workspace_endpoint" {
  description = "AMG Grafana UI URL (empty string when enable_amg = false)"
  value       = var.enable_amg ? "https://${aws_grafana_workspace.this[0].endpoint}" : ""
}
