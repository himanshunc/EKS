variable "project_name" {
  description = "Short project name — used as prefix in node group names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — nodes register to this cluster"
  type        = string
}

variable "node_role_arn" {
  description = "ARN of the EKS node IAM role — from iam module output"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of private subnets where nodes are launched — from vpc module output"
  type        = list(string)
}

variable "node_instance_types" {
  description = "EC2 instance types — first is preferred, rest are Spot fallback. Multiple types increase Spot availability"
  type        = list(string)
  default     = ["t3.medium", "t3.large"]
}

variable "node_disk_size" {
  description = "Root EBS volume size in GB for each node"
  type        = number
  default     = 50
}

variable "node_min_size" {
  description = "Minimum number of nodes in the Spot group — cluster never goes below this"
  type        = number
  default     = 1
}

variable "node_desired_size" {
  description = "Starting number of nodes — Cluster Autoscaler adjusts from here"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes — Cluster Autoscaler never exceeds this"
  type        = number
  default     = 4
}

variable "tags" {
  description = "Tags to apply to node group resources"
  type        = map(string)
  default     = {}
}
