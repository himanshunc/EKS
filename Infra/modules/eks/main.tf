# EKS Module - Step 5
# Creates:
#   - EKS cluster with KMS-encrypted secrets + audit logging
#   - OIDC provider (required for IRSA)
#   - vpc-cni and kube-proxy addons (reach ACTIVE without needing nodes)
#
# NOTE: CoreDNS is NOT here - it goes Degraded without nodes to schedule on.
#       CoreDNS lives in modules/eks_addons/ and runs after node_groups.

# --- EKS Cluster ---

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  version  = var.kubernetes_version
  role_arn = var.cluster_role_arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [var.cluster_sg_id]
    endpoint_public_access  = var.endpoint_public_access
    endpoint_private_access = true
    public_access_cidrs     = var.public_access_cidrs
  }

  # Encrypt Kubernetes Secrets at rest in etcd using KMS
  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = var.kms_key_arn
    }
  }

  # Audit logs to CloudWatch - "audit" records every kubectl command and API call
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  # Enable EKS Access Entry API alongside the legacy aws-auth ConfigMap.
  # API_AND_CONFIG_MAP allows IAM roles to be granted cluster access via
  # aws_eks_access_entry resources (Terraform-native, no ConfigMap editing needed).
  # bootstrap_cluster_creator_admin_permissions = true automatically gives
  # the IAM identity that creates the cluster full cluster-admin access.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = var.tags
}

# --- OIDC Provider ---

# Fetches the TLS thumbprint from the EKS OIDC issuer URL
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# Bridges Kubernetes service accounts and AWS IAM - required for IRSA
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = var.tags
}

# --- vpc-cni addon ---
# Assigns real VPC IPs to pods. Reaches ACTIVE without nodes (DaemonSet just waits
# to be scheduled). Must be present BEFORE nodes join so they get networking.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_update = "OVERWRITE"
}

# --- kube-proxy addon ---
# Manages iptables rules for ClusterIP services. Also reaches ACTIVE without nodes.
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_update = "OVERWRITE"
}
