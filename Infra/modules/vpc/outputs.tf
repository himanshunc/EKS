output "vpc_id" {
  description = "ID of the VPC — passed to security groups, EKS, and node groups"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC — used in security group rules"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of public subnets — used for internet-facing ALBs"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "IDs of private subnets — used for EKS nodes and internal ALBs"
  value       = [for s in aws_subnet.private : s.id]
}

output "nat_gateway_ids" {
  description = "IDs of NAT gateways — useful for auditing egress IPs"
  value       = [for nat in aws_nat_gateway.this : nat.id]
}

output "vpc_endpoint_s3_id" {
  description = "ID of the S3 VPC Gateway endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.s3[0].id : null
}
