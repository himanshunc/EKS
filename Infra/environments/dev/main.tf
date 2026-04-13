# Dev Environment - wires all modules together
#
# APPLY ORDER (dependency chain):
#   kms -> vpc -> security_groups -> iam -> eks -> irsa -> node_groups
#   -> ecr -> cluster_defaults -> helm_addons -> argocd -> monitoring -> logging
#
# KEY SPLIT: iam and irsa are separate modules to avoid a dependency cycle.
#   - iam   : cluster role + node role   (no OIDC needed, runs BEFORE eks)
#   - irsa  : all IRSA roles             (needs OIDC URL, runs AFTER eks)

terraform {
  # backend and versions are copied here by scripts/init.ps1
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }

  cluster_name       = "${var.project_name}-${var.environment}-eks-cluster"
  availability_zones = ["ap-south-1a", "ap-south-1b"]
}

# --- Step 1: KMS ---

module "kms" {
  source = "../../modules/kms"

  project_name = var.project_name
  environment  = var.environment
  tags         = local.common_tags
}

# --- Step 2: VPC ---

module "vpc" {
  source = "../../modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  aws_region           = var.aws_region
  cluster_name         = local.cluster_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = local.availability_zones
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]
  single_nat_gateway   = var.single_nat_gateway
  enable_vpc_endpoints = var.enable_vpc_endpoints
  tags                 = local.common_tags

  depends_on = [module.kms]
}

# --- Step 3: Security Groups ---

module "security_groups" {
  source = "../../modules/security_groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr
  tags         = local.common_tags

  depends_on = [module.vpc]
}

# --- Step 4: IAM (cluster role + node role only, no OIDC dependency) ---

module "iam" {
  source = "../../modules/iam"

  project_name = var.project_name
  environment  = var.environment
  github_org   = var.github_org
  github_repo  = var.github_repo
  tags         = local.common_tags
}

# --- Step 5: EKS (needs cluster_role_arn from iam) ---

module "eks" {
  source = "../../modules/eks"

  project_name           = var.project_name
  environment            = var.environment
  kubernetes_version     = var.kubernetes_version
  cluster_role_arn       = module.iam.cluster_role_arn
  kms_key_arn            = module.kms.key_arn
  private_subnet_ids     = module.vpc.private_subnet_ids
  cluster_sg_id          = module.security_groups.cluster_sg_id
  endpoint_public_access = var.eks_endpoint_public_access
  public_access_cidrs    = var.eks_public_access_cidrs
  tags                   = local.common_tags

  depends_on = [module.iam, module.kms, module.security_groups]
}

# --- Step 6: IRSA (needs OIDC provider from eks) ---

module "irsa" {
  source = "../../modules/irsa"

  project_name      = var.project_name
  environment       = var.environment
  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider     = module.eks.oidc_provider
  tags              = local.common_tags

  depends_on = [module.eks]
}

# --- Step 7: Node Groups (needs node_role_arn from iam, cluster from eks) ---

module "node_groups" {
  source = "../../modules/node_groups"

  project_name        = var.project_name
  environment         = var.environment
  cluster_name        = module.eks.cluster_name
  node_role_arn       = module.iam.node_role_arn
  private_subnet_ids  = module.vpc.private_subnet_ids
  node_instance_types = var.node_instance_types
  node_min_size       = var.node_min_size
  node_desired_size   = var.node_desired_size
  node_max_size       = var.node_max_size
  tags                = local.common_tags

  depends_on = [module.eks, module.iam]
}

# --- Step 8: ECR (no cluster dependency, can run in parallel) ---

module "ecr" {
  source = "../../modules/ecr"

  project_name     = var.project_name
  environment      = var.environment
  repository_names = var.ecr_repositories
  tags             = local.common_tags
}

# --- Step 8b: EKS Addons (after nodes are Ready) ---
# CoreDNS needs live nodes to schedule pods - must run after node_groups

module "eks_addons" {
  source = "../../modules/eks_addons"

  cluster_name = module.eks.cluster_name

  depends_on = [module.node_groups]
}

# --- Step 9: Cluster Defaults ---

module "cluster_defaults" {
  source = "../../modules/cluster_defaults"

  # "apps" gets the same LimitRange and default-deny NetworkPolicy as the other namespaces.
  # App-specific allow-ingress/egress policies live in k8s/apps/*/networkpolicy.yaml.
  extra_namespaces = ["apps"]

  depends_on = [module.eks_addons]
}

# --- Step 10: Helm Addons ---

module "helm_addons" {
  source = "../../modules/helm_addons"

  project_name                     = var.project_name
  environment                      = var.environment
  cluster_name                     = module.eks.cluster_name
  aws_region                       = var.aws_region
  vpc_id                           = module.vpc.vpc_id
  irsa_alb_controller_role_arn     = module.irsa.alb_controller_role_arn
  irsa_cluster_autoscaler_role_arn = module.irsa.cluster_autoscaler_role_arn
  irsa_ebs_csi_driver_role_arn     = module.irsa.ebs_csi_driver_role_arn

  depends_on = [module.eks_addons, module.cluster_defaults, module.irsa]
}

# --- Step 11: ArgoCD ---

module "argocd" {
  source = "../../modules/argocd"

  project_name = var.project_name
  environment  = var.environment

  depends_on = [module.helm_addons]
}

# --- Step 12: Monitoring ---

module "monitoring" {
  source = "../../modules/monitoring"

  project_name             = var.project_name
  environment              = var.environment
  aws_region               = var.aws_region
  irsa_amp_ingest_role_arn = module.irsa.amp_ingest_role_arn
  irsa_amg_role_arn        = module.irsa.amg_role_arn
  irsa_grafana_role_arn    = module.irsa.grafana_role_arn
  enable_amg               = var.enable_amg
  tags                     = local.common_tags

  depends_on = [module.helm_addons]
}

# --- Step 13: Logging ---

module "logging" {
  source = "../../modules/logging"

  project_name              = var.project_name
  environment               = var.environment
  cluster_name              = module.eks.cluster_name
  aws_region                = var.aws_region
  enable_container_insights = var.enable_container_insights
  tags                      = local.common_tags

  depends_on = [module.monitoring]
}
