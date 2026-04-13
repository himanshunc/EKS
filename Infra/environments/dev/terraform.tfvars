# ── Project ──────────────────────────────────────────────────────────────────

# Short project name — prefix for all resource names and tags
project_name = "gitops"

# Environment label — affects naming, NAT count, node sizes
# Allowed: "dev" | "staging" | "prod"
environment = "dev"

# Team responsible — shows in resource tags for cost attribution
owner = "himanshu-chaudhari"

# ── AWS ──────────────────────────────────────────────────────────────────────

# AWS region where all resources are created
aws_region = "ap-south-1"

# ── Kubernetes ───────────────────────────────────────────────────────────────

# EKS Kubernetes version — check AWS supported versions before changing
# https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
kubernetes_version = "1.34"

# ── Networking ───────────────────────────────────────────────────────────────

# VPC IP range — all subnets carved from this CIDR
vpc_cidr = "10.0.0.0/16"

# true  = one shared NAT gateway (~$32/month, fine for dev)
# false = one NAT per AZ (~$64/month, required for prod HA)
single_nat_gateway = true

# Enable VPC endpoints for S3, ECR, STS, EC2
# true = traffic stays on AWS network (faster + cheaper than NAT)
# Always true — only disable if debugging connectivity issues
enable_vpc_endpoints = true

# ── EKS Endpoint ─────────────────────────────────────────────────────────────

# true  = kubectl works from your laptop (great for learning)
# false = VPC-only access, need VPN or bastion (use in prod)
eks_endpoint_public_access = true

# Which IPs can reach the public endpoint
# "0.0.0.0/0" = everyone (fine for learning)
# ["x.x.x.x/32"] = your IP only (better practice)
eks_public_access_cidrs = ["0.0.0.0/0"]

# ── Node Groups ──────────────────────────────────────────────────────────────

# EC2 instance types — t3.large for both spot and on-demand
# t3.large: 2 vCPU, 8 GB RAM, 35 max pods/node (vs t3.medium's 4 GB RAM, 17 max pods)
# Better fit for the full stack: ArgoCD + monitoring + logging + system pods
node_instance_types = ["t3.large"]

# Node count for Spot group — start with 1, autoscale up to 2
# On-demand group always has 1 node (see node_groups module)
node_min_size     = 1
node_desired_size = 2
node_max_size     = 3

# ── ECR ──────────────────────────────────────────────────────────────────────

# Container image repositories to create (one per application)
ecr_repositories = ["api", "frontend", "worker"]

# ── Feature Flags ────────────────────────────────────────────────────────────

# Enable CloudWatch Container Insights (enhanced pod-level metrics)
# true is recommended — adds minimal cost, adds a lot of observability
enable_container_insights = true

# Enable Amazon Managed Grafana (AMG)
# false = AMG not available in ap-south-1 (Mumbai) — set to true in regions that support it
# Supported regions: https://aws.amazon.com/grafana/faqs/
enable_amg = false

# ── GitHub Actions CI ─────────────────────────────────────────────────────────

# GitHub organisation or user name that owns this repo
# Used to scope the OIDC trust: only workflows from THIS org/repo can assume the CI role
github_org = "himanshunc"

# GitHub repository name (without the org prefix)
# Example: if your repo is github.com/my-org/eks-claude → set this to "eks-claude"
github_repo = "EKS"
