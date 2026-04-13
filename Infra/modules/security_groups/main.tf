# ─────────────────────────────────────────────────────────────────────────────
# Security Groups Module — Step 3
# Two security groups:
#   1. Cluster SG  — controls access to the EKS control plane API endpoint
#   2. Node SG     — controls traffic between nodes and from nodes to control plane
#
# EKS managed node groups automatically add the cluster SG to nodes, so
# control-plane ↔ node communication is handled by AWS. We only need to
# add rules for application traffic (e.g. ALB → pods).
# ─────────────────────────────────────────────────────────────────────────────

# ─── Cluster Security Group ───────────────────────────────────────────────

# Controls access to the EKS API server endpoint.
# EKS attaches this to the control plane ENIs in your VPC.
resource "aws_security_group" "cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "EKS cluster control plane security group - controls API server access"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-cluster-sg"
  })
}

# Allow nodes to communicate with the cluster API server (kubelet, kube-proxy, etc.)
resource "aws_security_group_rule" "cluster_ingress_nodes" {
  security_group_id        = aws_security_group.cluster.id
  type                     = "ingress"
  description              = "Allow worker nodes to reach the EKS API server"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nodes.id
}

# Allow all outbound from the cluster SG — control plane needs to reach nodes
resource "aws_security_group_rule" "cluster_egress_all" {
  security_group_id = aws_security_group.cluster.id
  type              = "egress"
  description       = "Allow all outbound from EKS control plane"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# ─── Node Security Group ──────────────────────────────────────────────────

# Applied to all EKS worker nodes.
# Controls pod-to-pod, node-to-node, and ALB-to-pod traffic.
resource "aws_security_group" "nodes" {
  name        = "${local.name_prefix}-eks-nodes-sg"
  description = "EKS worker node security group - controls intra-cluster and inbound app traffic"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-nodes-sg"
  })
}

# Allow nodes to talk to each other — required for pod-to-pod communication
# (e.g. DNS queries, service mesh, cluster internal traffic)
resource "aws_security_group_rule" "nodes_ingress_self" {
  security_group_id        = aws_security_group.nodes.id
  type                     = "ingress"
  description              = "Allow all traffic between nodes - pod-to-pod, kubelet, etc."
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.nodes.id
}

# Allow the EKS control plane to communicate with nodes (webhook calls, health checks)
resource "aws_security_group_rule" "nodes_ingress_cluster" {
  security_group_id        = aws_security_group.nodes.id
  type                     = "ingress"
  description              = "Allow EKS control plane to reach nodes (health checks, webhooks)"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.cluster.id
}

# Allow the ALB to reach pods on their NodePort range
resource "aws_security_group_rule" "nodes_ingress_alb" {
  security_group_id = aws_security_group.nodes.id
  type              = "ingress"
  description       = "Allow ALB to reach NodePort services on worker nodes"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr] # only from within the VPC — ALBs are VPC-internal
}

# Allow all outbound from nodes — they need to reach ECR, S3, AWS APIs, etc.
resource "aws_security_group_rule" "nodes_egress_all" {
  security_group_id = aws_security_group.nodes.id
  type              = "egress"
  description       = "Allow all outbound - nodes pull images, call AWS APIs, etc."
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}
