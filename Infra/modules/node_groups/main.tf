# ─────────────────────────────────────────────────────────────────────────────
# Node Groups Module — Step 6
# Creates two managed node groups:
#   1. Spot (primary)    — t3.medium + t3.large, 1–4 nodes, cheaper
#   2. On-Demand (fallback) — t3.medium, 0–2 nodes, for workloads that can't use Spot
#
# WHY SPOT?
# Spot instances can be 60–90% cheaper than on-demand.
# With Node Termination Handler deployed, Spot interruptions (2-min warning)
# result in graceful pod drains — no abrupt kills.
#
# WHY MANAGED NODE GROUPS?
# AWS handles AMI updates, node lifecycle, and the Auto Scaling Group.
# You only configure sizing, instance types, and labels.
# ─────────────────────────────────────────────────────────────────────────────

# ─── Launch Template ──────────────────────────────────────────────────────

# Launch template for all node groups.
# Configures the EBS root volume to use gp3 (cheaper + faster IOPS than gp2).
resource "aws_launch_template" "nodes" {
  name_prefix            = "${local.name_prefix}-node-lt-"
  description            = "Launch template for EKS nodes - gp3 root volume"
  update_default_version = true # always make the latest version the default

  block_device_mappings {
    device_name = "/dev/xvda" # root volume on Amazon Linux 2

    ebs {
      volume_size           = var.node_disk_size # GB
      volume_type           = "gp3"              # gp3 is ~20% cheaper than gp2 with same baseline IOPS
      delete_on_termination = true               # clean up EBS volumes when node is terminated
      encrypted             = true               # encrypt node volumes at rest
    }
  }

  # Metadata service v2 (IMDSv2) — required security hardening.
  # Prevents SSRF attacks from pods trying to steal instance credentials.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # forces IMDSv2, blocks IMDSv1
    http_put_response_hop_limit = 2          # allows containers to reach the metadata service (hop: node → container)
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${local.name_prefix}-eks-node"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${local.name_prefix}-eks-node-volume"
    })
  }

  lifecycle {
    create_before_destroy = true # replace template before removing old one — zero downtime
  }
}

# ─── Spot Node Group (Primary) ────────────────────────────────────────────

# Primary node group using Spot instances.
# capacity_type = "SPOT" tells EKS managed node groups to use Spot pricing.
# Multiple instance types increase the chance of getting Spot capacity.
resource "aws_eks_node_group" "spot" {
  cluster_name    = var.cluster_name
  node_group_name = "${local.name_prefix}-spot"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids
  capacity_type   = "SPOT" # use Spot pricing — 60-90% cheaper than on-demand

  # Multiple instance types = higher Spot availability (EKS picks from the pool)
  instance_types = var.node_instance_types

  scaling_config {
    min_size     = var.node_min_size
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
  }

  # Use the launch template for gp3 volumes and IMDSv2
  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  # Taint Spot nodes so critical system pods avoid them unless tolerations are set.
  # Comment this out if you want all workloads to use Spot by default.
  # taint {
  #   key    = "spot"
  #   value  = "true"
  #   effect = "NO_SCHEDULE"
  # }

  # Labels — used by node selectors and Pod topology spread constraints
  labels = {
    role         = "spot"
    "node-type"  = "spot"
  }

  # Lifecycle — prevent replacement from destroying nodes with running pods first
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size] # let Cluster Autoscaler manage desired_size
  }

  update_config {
    max_unavailable_percentage = 33 # roll 33% of nodes at a time during updates (zero downtime)
  }

  tags = merge(var.tags, {
    Name                                        = "${local.name_prefix}-spot-node-group"
    "k8s.io/cluster-autoscaler/enabled"         = "true"             # tag required by Cluster Autoscaler discovery
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"        # scopes autoscaler to this cluster
  })
}

# ─── On-Demand Node Group (Fallback) ─────────────────────────────────────

# Fallback node group for workloads that can't run on Spot (e.g. stateful services,
# or anything with PodDisruptionBudget that Spot interruptions could violate).
resource "aws_eks_node_group" "on_demand" {
  cluster_name    = var.cluster_name
  node_group_name = "${local.name_prefix}-on-demand"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids
  capacity_type   = "ON_DEMAND" # guaranteed capacity — pay full price

  instance_types = [var.node_instance_types[0]] # use only the primary instance type for on-demand

  scaling_config {
    min_size     = 1 # always keep 1 on-demand node for system workloads
    desired_size = 1
    max_size     = 2
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  labels = {
    role        = "on-demand"
    "node-type" = "on-demand"
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  update_config {
    max_unavailable_percentage = 50
  }

  tags = merge(var.tags, {
    Name                                            = "${local.name_prefix}-on-demand-node-group"
    "k8s.io/cluster-autoscaler/enabled"             = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  })
}
