variable "project_name" {
  description = "Short project name - used as prefix for all IAM role and policy names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all IAM resources"
  type        = map(string)
  default     = {}
}

variable "github_org" {
  description = "GitHub organisation or user name that owns this repo (e.g. 'my-org'). Used to scope the GitHub Actions OIDC trust policy."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name without the org prefix (e.g. 'eks-claude'). Used to scope the GitHub Actions OIDC trust policy."
  type        = string
}
