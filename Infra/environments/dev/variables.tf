# ── Project ──────────────────────────────────────────────────────────────────

variable "project_name" {
  description = "Short project name — prefix for all resource names and tags"
  type        = string
}

variable "environment" {
  description = "Environment label — affects naming, NAT count, node sizes. Allowed: dev | staging | prod"
  type        = string
}

variable "owner" {
  description = "Team or person responsible — shown in resource tags for cost attribution"
  type        = string
}

# ── AWS ──────────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region where all resources are created"
  type        = string
  default     = "ap-south-1"
}

# ── Kubernetes ───────────────────────────────────────────────────────────────

variable "kubernetes_version" {
  description = "EKS Kubernetes version — check AWS docs before upgrading"
  type        = string
  default     = "1.29"
}

# ── Networking ───────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "VPC IP range — all subnets carved from this CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  description = "true = one shared NAT (~$32/month, fine for dev). false = one per AZ (prod HA)"
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Create VPC endpoints — keeps AWS API traffic off the NAT gateway"
  type        = bool
  default     = true
}

# ── EKS Endpoint ─────────────────────────────────────────────────────────────

variable "eks_endpoint_public_access" {
  description = "true = kubectl from laptop. false = VPN/bastion required (prod)"
  type        = bool
  default     = true
}

variable "eks_public_access_cidrs" {
  description = "IPs allowed to reach the public API endpoint. Use your IP in prod"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ── Node Groups ──────────────────────────────────────────────────────────────

variable "node_instance_types" {
  description = "EC2 instance types — first preferred, rest are Spot fallback"
  type        = list(string)
  default     = ["t3.medium", "t3.large"]
}

variable "node_min_size" {
  description = "Minimum nodes in Spot group — cluster never goes below this"
  type        = number
  default     = 1
}

variable "node_desired_size" {
  description = "Starting node count — Cluster Autoscaler adjusts from here"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum nodes — Cluster Autoscaler never exceeds this"
  type        = number
  default     = 4
}

# ── ECR ──────────────────────────────────────────────────────────────────────

variable "ecr_repositories" {
  description = "Container image repositories to create (one per application)"
  type        = list(string)
  default     = ["api", "frontend", "worker"]
}

# ── Feature Flags ────────────────────────────────────────────────────────────

variable "enable_container_insights" {
  description = "true = install CloudWatch Container Insights (enhanced pod-level metrics)"
  type        = bool
  default     = true
}

variable "enable_amg" {
  description = "true = create Amazon Managed Grafana workspace. false = skip (use when AMG unavailable in region)"
  type        = bool
  default     = false
}

# ── GitHub Actions CI ─────────────────────────────────────────────────────────

variable "github_org" {
  description = "GitHub organisation or user name that owns this repo — used to scope the OIDC trust policy for CI"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without org prefix) — used to scope the OIDC trust policy for CI"
  type        = string
}
