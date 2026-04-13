# Providers — configured at environment level (environments/dev/main.tf)
# The Kubernetes and Helm providers are configured dynamically using EKS outputs,
# so they must be set up AFTER the EKS cluster exists (in the environment main.tf).

# AWS provider — region comes from the environment variable
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  }
}

# Kubernetes provider — uses EKS cluster endpoint + CA cert + token.
# exec block fetches a short-lived token using the AWS CLI (no static credentials).
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# Helm provider — same auth as Kubernetes provider.
# Used to deploy ALB controller, metrics-server, ArgoCD, etc.
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# NOTE: Grafana provider is not configured here.
# AMG data sources are set up manually after the workspace is created.
# See docs/grafana-dashboards.md for step-by-step instructions.
