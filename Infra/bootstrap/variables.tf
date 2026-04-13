variable "aws_region" {
  description = "AWS region where the bootstrap resources will be created"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Short project name — used as prefix for S3 bucket and DynamoDB table names"
  type        = string
  default     = "myapp"
}
