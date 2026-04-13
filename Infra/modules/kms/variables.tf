variable "project_name" {
  description = "Short project name — used as a prefix in the KMS key alias"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod) — used in key alias and description"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all KMS resources"
  type        = map(string)
  default     = {}
}
