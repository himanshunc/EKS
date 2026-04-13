output "cluster_sg_id" {
  description = "ID of the EKS cluster security group — passed to the eks module"
  value       = aws_security_group.cluster.id
}

output "node_sg_id" {
  description = "ID of the EKS node security group — passed to the node_groups module"
  value       = aws_security_group.nodes.id
}
