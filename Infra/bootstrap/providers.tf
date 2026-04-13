provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "eks-bootstrap"
      ManagedBy   = "Terraform"
      Environment = "global"
    }
  }
}
