locals {
  # Resource name prefix — all VPC resources share this prefix
  name_prefix = "${var.project_name}-${var.environment}"

  # Availability zones — used to distribute subnets across AZs
  azs = var.availability_zones
}
