terraform {
  required_version = ">= 1.6.0"

  required_providers {
    # AWS provider — used to create S3 bucket and DynamoDB table
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
