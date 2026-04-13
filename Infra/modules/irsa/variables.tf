variable "project_name" {
  description = "Short project name - used as prefix for all IRSA role and policy names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name - used to scope Cluster Autoscaler permissions to this cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider - from eks module output, used in IRSA trust policies"
  type        = string
}

variable "oidc_provider" {
  description = "Hostname of the EKS OIDC provider without https:// - used in IRSA trust policy conditions"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all IRSA resources"
  type        = map(string)
  default     = {}
}
