variable "project_name" {
  description = "Short project name — used as prefix in security group names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where security groups will be created — from vpc module output"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block — used to restrict ALB-to-node ingress to VPC traffic only"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all security group resources"
  type        = map(string)
  default     = {}
}
