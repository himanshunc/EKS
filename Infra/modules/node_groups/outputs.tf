output "spot_node_group_name" {
  description = "Name of the Spot managed node group"
  value       = aws_eks_node_group.spot.node_group_name
}

output "on_demand_node_group_name" {
  description = "Name of the On-Demand managed node group"
  value       = aws_eks_node_group.on_demand.node_group_name
}

output "launch_template_id" {
  description = "ID of the shared launch template — useful for troubleshooting node configuration"
  value       = aws_launch_template.nodes.id
}
