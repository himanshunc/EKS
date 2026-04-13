# IAM Module - Step 4
# Creates only the roles that are needed BEFORE the EKS cluster exists:
#   - EKS cluster role  (control plane assumes this to manage AWS resources)
#   - EKS node role     (worker nodes assume this to join cluster + pull images)
#
# IRSA roles (which need the OIDC provider URL from EKS) live in modules/irsa/
# and are applied after the cluster is created.

# --- EKS Cluster Role ---

# Trust policy - allows the EKS service to assume this role.
# Required so EKS can call AWS APIs (create ENIs, manage SGs, etc.)
resource "aws_iam_role" "eks_cluster" {
  name        = "${local.name_prefix}-eks-cluster-role"
  description = "IAM role for EKS control plane"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

# AmazonEKSClusterPolicy - AWS managed policy required for EKS cluster operations
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# --- EKS Node Role ---

# Trust policy - allows EC2 instances (worker nodes) to assume this role.
resource "aws_iam_role" "eks_node" {
  name        = "${local.name_prefix}-eks-node-role"
  description = "IAM role for EKS worker nodes"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

# AmazonEKSWorkerNodePolicy - allows nodes to call EKS APIs to register themselves
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# AmazonEKS_CNI_Policy - allows the VPC CNI plugin to manage pod network interfaces
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# AmazonEC2ContainerRegistryReadOnly - allows nodes to pull images from ECR
resource "aws_iam_role_policy_attachment" "eks_ecr_read" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# CloudWatchAgentServerPolicy - allows FluentBit and Container Insights to ship logs/metrics
resource "aws_iam_role_policy_attachment" "eks_cloudwatch" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# AMP read permissions - allows Grafana (running on nodes) to query AMP metrics.
# Grafana 11 does not reliably resolve IRSA credentials for SigV4 signing.
# Using the node role via EC2 IMDSv2 is the reliable fallback for in-cluster Grafana.
# Scope: query-only (no write). Prometheus agent uses its own IRSA role for remote_write.
resource "aws_iam_policy" "amp_query" {
  name        = "${local.name_prefix}-node-amp-query"
  description = "Allows Grafana on EKS nodes to query AMP metrics"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "aps:QueryMetrics",
        "aps:GetSeries",
        "aps:GetLabels",
        "aps:GetMetricMetadata"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "amp_query" {
  role       = aws_iam_role.eks_node.name
  policy_arn = aws_iam_policy.amp_query.arn
}

# --- GitHub Actions OIDC ---
# Lets GitHub Actions authenticate to AWS without static access keys.
# GitHub's OIDC provider issues a short-lived token per workflow run;
# this IAM role trusts that token and grants ECR push permissions.
# Docs: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services

# GitHub Actions OIDC provider — tells AWS to trust tokens signed by GitHub.
# The thumbprint is the SHA-1 of GitHub's OIDC certificate; it rarely changes.
resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # GitHub's OIDC certificate thumbprint — stable, sourced from GitHub docs.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = var.tags
}

# IAM role that GitHub Actions workflows assume via OIDC.
# Scoped to a specific repo so only workflows in THIS repo can assume it.
resource "aws_iam_role" "github_actions" {
  name        = "${local.name_prefix}-github-actions"
  description = "Role assumed by GitHub Actions via OIDC - used for ECR push in CI"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github_actions.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # Only allow tokens from this specific repo — not any GitHub repo
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # repo:ORG/REPO:* matches all branches, tags, and PR events in the repo
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
        }
      }
    }]
  })

  tags = var.tags
}

# Policy: ECR push — allows CI to build and push Docker images to ECR.
# GetAuthorizationToken is account-level (Resource = "*" required by AWS).
# Push actions are scoped to repos in this account; tighten to specific repo ARNs in prod.
resource "aws_iam_policy" "github_actions_ecr" {
  name        = "${local.name_prefix}-github-actions-ecr"
  description = "Allows GitHub Actions CI to push Docker images to ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # GetAuthorizationToken must be * — it's account-scoped, not repo-scoped
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        # All push actions needed to upload a Docker image layer-by-layer
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeRepositories"
        ]
        # Scoped to all ECR repos in this account/region — tighten to specific ARNs in prod
        Resource = "arn:aws:ecr:*:*:repository/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_ecr.arn
}

# --- Terraform CI OIDC Role ---
# Separate role for the terraform-plan and terraform-apply workflows.
# Needs broad AWS permissions to create/destroy the full stack (EKS, VPC, IAM, etc.).
# AdministratorAccess is used here for simplicity — tighten to specific services in prod.
resource "aws_iam_role" "github_actions_terraform" {
  name        = "${local.name_prefix}-github-actions-terraform"
  description = "Role assumed by GitHub Actions Terraform CI via OIDC - plan and apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github_actions.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
        }
      }
    }]
  })

  tags = var.tags
}

# AdministratorAccess — required to create/destroy EKS, VPC, IAM, KMS, ECR, ALB etc.
# Scope this down to specific services if using this pattern in production.
resource "aws_iam_role_policy_attachment" "github_actions_terraform" {
  role       = aws_iam_role.github_actions_terraform.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
