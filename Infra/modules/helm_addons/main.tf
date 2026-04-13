# ─────────────────────────────────────────────────────────────────────────────
# Helm Addons Module — Step 9
# Deploys cluster-level Helm add-ons in order:
#   1. AWS Load Balancer Controller  — creates ALBs from Kubernetes Ingress
#   2. Metrics Server               — enables kubectl top + HPA
#   3. Cluster Autoscaler           — scales nodes up/down based on pod demand
#   4. EBS CSI Driver               — allows pods to use EBS PersistentVolumes
#   5. Node Termination Handler     — graceful drain on Spot interruption
# ─────────────────────────────────────────────────────────────────────────────

# ─── AWS Load Balancer Controller ─────────────────────────────────────────

# ALB Controller — watches Kubernetes Ingress resources and creates AWS ALBs.
# Without this, you can't expose services to the internet via ALB.
# The IRSA role annotation tells the controller pod to use the ALB IAM role.
resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.1"

  # Wait for the deployment to be fully ready before Terraform marks this done.
  # CRITICAL: ALB controller registers a mutating webhook. All other charts must
  # wait until this pod is Running — otherwise the webhook has no endpoints and
  # any chart that creates a Service resource will fail with "no endpoints available".
  wait    = true
  timeout = 300

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.irsa_alb_controller_role_arn # IRSA annotation — pod gets ALB IAM permissions
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  # Only 1 replica in dev — increase to 2 in prod for HA
  set {
    name  = "replicaCount"
    value = "1"
  }
}

# ─── Metrics Server ───────────────────────────────────────────────────────

# Metrics Server — collects CPU and memory usage from the kubelet on each node.
# Required for:
#   - `kubectl top pods` / `kubectl top nodes`
#   - Horizontal Pod Autoscaler (HPA) to make scaling decisions
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.0"

  set {
    name  = "args[0]"
    value = "--kubelet-preferred-address-types=InternalIP" # use node IP, not hostname (required in EKS)
  }

  # Wait for ALB controller pod + webhook to be Ready before installing anything else
  depends_on = [helm_release.alb_controller]
}

# ─── Cluster Autoscaler ───────────────────────────────────────────────────

# Cluster Autoscaler — monitors pending pods and scales node groups up.
# When nodes are underutilised, it scales them down (saves cost).
# The IRSA role gives it permission to modify Auto Scaling Groups.
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.37.0"

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name # uses the cluster tag to discover node groups automatically
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  # Pin the service account name so it matches the IRSA trust policy exactly.
  # Default is "{release-name}-aws-cluster-autoscaler" which would not match.
  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.irsa_cluster_autoscaler_role_arn
  }

  # Scale down safely — wait 10 minutes of underutilisation before removing a node
  set {
    name  = "extraArgs.scale-down-delay-after-add"
    value = "10m"
  }

  set {
    name  = "extraArgs.scale-down-unneeded-time"
    value = "10m"
  }

  depends_on = [helm_release.alb_controller]
}

# ─── EBS CSI Driver ───────────────────────────────────────────────────────

# EBS CSI Driver — allows Kubernetes to create and attach EBS volumes dynamically.
# Without this, PersistentVolumeClaims (PVCs) using the gp3 storage class won't work.
resource "helm_release" "ebs_csi_driver" {
  name       = "aws-ebs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart      = "aws-ebs-csi-driver"
  namespace  = "kube-system"
  version    = "2.31.0"

  set {
    name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.irsa_ebs_csi_driver_role_arn
  }

  depends_on = [helm_release.alb_controller]
}

# Default StorageClass — gp3 volumes provisioned on-demand for PVCs.
# gp3 is cheaper and faster than gp2 (AWS's previous default).
resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true" # makes this the default PVC storage class
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"           # delete EBS volume when PVC is deleted — change to Retain in prod
  volume_binding_mode    = "WaitForFirstConsumer" # only provision when a pod is scheduled (respects AZ)
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true" # encrypt EBS volumes at rest
  }
}

# ─── Node Termination Handler ─────────────────────────────────────────────

# Node Termination Handler — listens for AWS Spot interruption notices (2-min warning)
# and gracefully drains the node before AWS reclaims it.
# Without this, pods are killed abruptly when a Spot instance is interrupted.
# Also handles scheduled maintenance events and instance health events.
resource "helm_release" "node_termination_handler" {
  name       = "aws-node-termination-handler"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-node-termination-handler"
  namespace  = "kube-system"
  version    = "0.21.0"

  set {
    name  = "enableSqsTerminationDraining"
    value = "false" # IMDSv2 mode (simpler than SQS mode for learning)
  }

  set {
    name  = "nodeSelector.node-type"
    value = "spot" # only run on Spot nodes — no need on on-demand nodes
  }

  depends_on = [helm_release.alb_controller]
}
