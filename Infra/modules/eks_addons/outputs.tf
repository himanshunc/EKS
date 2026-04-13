output "coredns_id" {
  description = "ID of the CoreDNS addon"
  value       = aws_eks_addon.coredns.id
}
