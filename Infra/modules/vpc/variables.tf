variable "project_name" {
  description = "Short project name — used as prefix for all VPC resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region — used to construct VPC endpoint service names"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — used in the kubernetes.io/cluster subnet tag required by EKS"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (e.g. 10.0.0.0/16)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to deploy subnets into — must have at least 2 for EKS HA"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets — one per AZ, in the same order as availability_zones"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets — one per AZ, in the same order as availability_zones"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "single_nat_gateway" {
  description = "true = one shared NAT (~$32/month, fine for dev). false = one per AZ (~$64/month, required for prod HA)"
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Create VPC endpoints for S3, ECR, STS, EC2 — keeps AWS API traffic off the NAT gateway (free + faster)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all VPC resources"
  type        = map(string)
  default     = {}
}
