variable "project_name" {
  description = "Short project name — used as prefix in resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — used to name the CloudWatch log group"
  type        = string
}

variable "aws_region" {
  description = "AWS region — passed to FluentBit CloudWatch output plugin"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain container logs in CloudWatch before automatic deletion"
  type        = number
  default     = 30
}

variable "enable_container_insights" {
  description = "true = install CloudWatch Container Insights EKS add-on (enhanced pod-level metrics)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to CloudWatch log group"
  type        = map(string)
  default     = {}
}
