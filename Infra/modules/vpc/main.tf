# ─────────────────────────────────────────────────────────────────────────────
# VPC Module — Step 2
# Creates the full network layer:
#   - VPC
#   - Public subnets (2 AZs) — for internet-facing ALBs
#   - Private subnets (2 AZs) — for EKS nodes and internal ALBs
#   - Internet Gateway — allows public subnets to reach the internet
#   - NAT Gateway — allows private subnets to reach the internet (outbound only)
#   - Route tables — one for public, one for private
#   - VPC Endpoints — S3, ECR API, ECR DKR, STS, EC2
#
# WHY VPC ENDPOINTS?
# Without them, ECR image pulls and AWS API calls route through the NAT gateway.
# You pay per-GB NAT charges and add latency. Endpoints keep traffic on the
# AWS private backbone — free and faster.
# ─────────────────────────────────────────────────────────────────────────────

# ─── VPC ──────────────────────────────────────────────────────────────────

# Main VPC — all resources live inside this network boundary.
# enable_dns_hostnames = true is required for EKS nodes to resolve their own hostnames.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true  # allows DNS resolution within the VPC
  enable_dns_hostnames = true  # assigns DNS hostnames to EC2 instances (required for EKS)

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# ─── Subnets ──────────────────────────────────────────────────────────────

# Public subnets — one per AZ, used for internet-facing ALBs.
# map_public_ip_on_launch = true so anything deployed here gets a public IP.
# Tag "kubernetes.io/role/elb" = "1" tells the ALB controller to use these subnets.
resource "aws_subnet" "public" {
  for_each = { for idx, az in local.azs : az => var.public_subnet_cidrs[idx] }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true # public subnets assign public IPs to instances

  tags = merge(var.tags, {
    Name                     = "${local.name_prefix}-public-${each.key}"
    "kubernetes.io/role/elb" = "1" # ALB controller uses this tag to find public subnets
  })
}

# Private subnets — one per AZ, used for EKS worker nodes and internal ALBs.
# Nodes here reach the internet via the NAT gateway (outbound only).
# Tags tell the ALB controller and EKS which subnets to use.
resource "aws_subnet" "private" {
  for_each = { for idx, az in local.azs : az => var.private_subnet_cidrs[idx] }

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(var.tags, {
    Name                                        = "${local.name_prefix}-private-${each.key}"
    "kubernetes.io/role/internal-elb"           = "1"              # internal ALB subnet tag
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"          # EKS node subnet tag
  })
}

# ─── Internet Gateway ─────────────────────────────────────────────────────

# Internet Gateway — attaches to the VPC and provides internet access for public subnets.
# Without this, nothing in public subnets can reach or be reached from the internet.
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# ─── NAT Gateway ──────────────────────────────────────────────────────────

# Elastic IP for the NAT gateway — static IP that identifies outbound traffic.
resource "aws_eip" "nat" {
  # In dev: single_nat_gateway = true → one EIP. In prod: one per AZ.
  for_each = var.single_nat_gateway ? { "single" = "ap-south-1a" } : { for az in local.azs : az => az }

  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-nat-eip-${each.key}"
  })

  depends_on = [aws_internet_gateway.this] # EIP requires IGW to be attached first
}

# NAT Gateway — sits in a public subnet and allows private subnet instances to
# make outbound internet requests (e.g. pull container images, reach AWS APIs).
# single_nat_gateway = true in dev saves ~$32/month vs. one per AZ.
resource "aws_nat_gateway" "this" {
  for_each = aws_eip.nat

  allocation_id = each.value.id
  # Always place NAT in the first public subnet AZ
  subnet_id = aws_subnet.public[
    var.single_nat_gateway ? local.azs[0] : each.key
  ].id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-nat-${each.key}"
  })

  depends_on = [aws_internet_gateway.this]
}

# ─── Route Tables ─────────────────────────────────────────────────────────

# Public route table — all traffic (0.0.0.0/0) goes through the Internet Gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rt-public"
  })
}

# Associate each public subnet with the public route table
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Private route tables — one per NAT gateway (one in dev, one per AZ in prod).
# Traffic to 0.0.0.0/0 routes through the NAT gateway (outbound only).
resource "aws_route_table" "private" {
  for_each = aws_nat_gateway.this

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = each.value.id
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rt-private-${each.key}"
  })
}

# Associate each private subnet with the correct private route table.
# In dev: all private subnets share the single route table.
# In prod: each AZ's subnet uses its own route table (AZ-local NAT).
resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id = each.value.id
  route_table_id = var.single_nat_gateway ? (
    aws_route_table.private["single"].id
  ) : (
    aws_route_table.private[each.key].id
  )
}

# ─── VPC Endpoints ────────────────────────────────────────────────────────

# S3 Gateway Endpoint — free, no interface, routes S3 traffic within AWS network.
# EKS nodes pull ECR layers from S3; this avoids NAT charges for those transfers.
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway" # Gateway type is free and routes via route tables

  route_table_ids = concat(
    [aws_route_table.public.id],
    [for rt in aws_route_table.private : rt.id]
  )

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpce-s3"
  })
}

# ECR API Interface Endpoint — allows nodes to call ECR control plane (describe, auth).
# Without this, ECR API calls leave the VPC through the NAT gateway.
resource "aws_vpc_endpoint" "ecr_api" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true # overrides public DNS — traffic stays private

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpce-ecr-api"
  })
}

# ECR DKR Interface Endpoint — Docker registry endpoint used to pull images.
# This is the endpoint that handles the actual image layer downloads from ECR.
resource "aws_vpc_endpoint" "ecr_dkr" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpce-ecr-dkr"
  })
}

# STS Interface Endpoint — AWS Security Token Service.
# IRSA (IAM Roles for Service Accounts) calls STS to exchange OIDC tokens for IAM creds.
resource "aws_vpc_endpoint" "sts" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpce-sts"
  })
}

# EC2 Interface Endpoint — used by node bootstrap scripts and Cluster Autoscaler.
# Autoscaler calls EC2 APIs (DescribeInstances, etc.) to make scaling decisions.
resource "aws_vpc_endpoint" "ec2" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpce-ec2"
  })
}

# ─── Security Group for VPC Endpoints ─────────────────────────────────────

# Security group for all Interface VPC endpoints.
# Only allows HTTPS (443) from within the VPC — endpoints only serve TLS traffic.
resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.name_prefix}-vpce-sg"
  description = "Allow HTTPS traffic from within the VPC to VPC Interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC - required for all Interface endpoint traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound - needed for endpoint health checks"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpce-sg"
  })
}
