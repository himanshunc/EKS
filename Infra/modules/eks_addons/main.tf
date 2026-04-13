# EKS Addons Module - runs AFTER node_groups
# Only CoreDNS lives here - it goes Degraded without live nodes to schedule on.
# vpc-cni and kube-proxy are in the eks module (they reach ACTIVE without nodes).
#
# Dependency order: eks -> node_groups -> eks_addons

# CoreDNS - DNS server for the cluster. Needs nodes to schedule its 2 pods.
# Runs here (after node_groups) so it finds Ready nodes and reaches ACTIVE.
resource "aws_eks_addon" "coredns" {
  cluster_name                = var.cluster_name
  addon_name                  = "coredns"
  resolve_conflicts_on_update = "OVERWRITE"
}
