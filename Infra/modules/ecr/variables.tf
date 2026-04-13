variable "project_name" {
  description = "Short project name — used as prefix in ECR repository names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "repository_names" {
  description = "List of application names — one ECR repository is created per name (e.g. [\"api\", \"frontend\", \"worker\"])"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to all ECR resources"
  type        = map(string)
  default     = {}
}
