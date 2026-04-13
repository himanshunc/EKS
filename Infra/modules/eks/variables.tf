variable "project_name" {
  description = "Short project name — used to build the cluster name"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster — check AWS supported versions before changing"
  type        = string
  default     = "1.29"
}

variable "cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role — from the iam module output"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt EKS secrets — from the kms module output"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of private subnets where the EKS control plane ENIs are placed — from vpc module output"
  type        = list(string)
}

variable "cluster_sg_id" {
  description = "ID of the cluster security group — from security_groups module output"
  type        = string
}

variable "endpoint_public_access" {
  description = "true = kubectl works from laptop. false = VPN/bastion required (use in prod)"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Use your IP in prod, 0.0.0.0/0 for learning"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Tags to apply to all EKS resources"
  type        = map(string)
  default     = {}
}
