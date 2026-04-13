variable "project_name" {
  description = "Short project name — used in AMP and AMG workspace names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region — used in SigV4 authentication for AMP remote write and CloudWatch data source"
  type        = string
}

variable "irsa_amp_ingest_role_arn" {
  description = "IRSA role ARN for Prometheus agent — allows remote-writing metrics to AMP"
  type        = string
}

variable "irsa_amg_role_arn" {
  description = "IAM role ARN for AMG workspace — allows Grafana to query AMP and CloudWatch"
  type        = string
}

variable "irsa_grafana_role_arn" {
  description = "IRSA role ARN for in-cluster Grafana OSS — allows the Grafana pod to query AMP via SigV4"
  type        = string
}

variable "enable_amg" {
  description = "true = create Amazon Managed Grafana workspace. false = skip AMG (use when AMG is not available in your region, e.g. ap-south-1)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to AMP and AMG resources"
  type        = map(string)
  default     = {}
}
