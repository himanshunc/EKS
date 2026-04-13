# ─────────────────────────────────────────────────────────────────────────────
# Cluster Defaults Module — Step 8
# Applies sane Kubernetes-level defaults immediately after nodes are ready:
#
#   1. Namespaces       — creates standard namespaces
#   2. LimitRange       — prevents runaway pods from consuming all node resources
#   3. NetworkPolicy    — deny-all by default (pods must explicitly allow traffic)
#   4. PodDisruptionBudgets — ensures system components survive node drains
#
# This module is the most educational for learning Kubernetes resource management.
# ─────────────────────────────────────────────────────────────────────────────

# ─── Namespaces ───────────────────────────────────────────────────────────

# Standard namespaces — created here so other modules can deploy into them.
# Using for_each ensures clean destroy (each namespace is a separate resource).
resource "kubernetes_namespace" "standard" {
  # Create all managed namespaces except default and kube-system (those already exist in every cluster).
  # This includes the hardcoded list plus any extra_namespaces passed in (e.g. "apps").
  for_each = setsubtract(local.managed_namespaces, ["default", "kube-system"])

  metadata {
    name = each.value
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# ─── LimitRange ───────────────────────────────────────────────────────────

# LimitRange per namespace — sets default resource requests and limits for containers
# that don't specify their own. Without this, a pod with no limits can consume
# all CPU/memory on a node and starve other pods.
resource "kubernetes_limit_range" "default" {
  for_each = local.managed_namespaces

  metadata {
    name      = "default-limits"
    namespace = each.value
  }

  spec {
    limit {
      type = "Container"

      # Default limits — applied when a container doesn't specify limits
      default = {
        cpu    = "500m"  # 0.5 vCPU maximum
        memory = "256Mi" # 256MB maximum
      }

      # Default requests — applied when a container doesn't specify requests.
      # Requests affect scheduling: scheduler places pod on a node with enough free capacity.
      default_request = {
        cpu    = "100m"  # 0.1 vCPU reserved
        memory = "128Mi" # 128MB reserved
      }

      # Hard caps — no container in this namespace can exceed these
      max = {
        cpu    = "2"    # 2 vCPU maximum — change for CPU-intensive workloads
        memory = "1Gi"  # 1GB maximum — increase for memory-intensive workloads
      }
    }
  }
}

# ─── Default-Deny NetworkPolicy ───────────────────────────────────────────

# Deny all ingress and egress for every pod by default.
# This is the Kubernetes equivalent of a default-deny firewall rule.
# Add explicit allow policies for each service that needs to communicate.
#
# NOTE: kube-system is excluded because system components need unrestricted access.
resource "kubernetes_network_policy" "default_deny" {
  for_each = setsubtract(local.managed_namespaces, ["kube-system"])

  metadata {
    name      = "default-deny-all"
    namespace = each.value
  }

  spec {
    # Empty pod_selector = applies to ALL pods in the namespace
    pod_selector {}

    # Explicitly deny both directions
    policy_types = ["Ingress", "Egress"]

    # No ingress rules = deny all inbound
    # No egress rules = deny all outbound
  }
}

# Allow DNS egress from all namespaces — pods need to resolve service names.
# Without this, the default-deny policy would block DNS and break everything.
resource "kubernetes_network_policy" "allow_dns_egress" {
  for_each = setsubtract(local.managed_namespaces, ["kube-system"])

  metadata {
    name      = "allow-dns-egress"
    namespace = each.value
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      # Allow UDP 53 (DNS) to kube-system — where CoreDNS runs
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
      }
    }
  }
}

# ─── PodDisruptionBudgets ─────────────────────────────────────────────────

# PDB for CoreDNS — ensures at least 1 DNS pod is always running during node drains.
# Without this, a rolling node upgrade could drain both CoreDNS pods at once,
# breaking DNS resolution for all pods in the cluster.
resource "kubernetes_pod_disruption_budget_v1" "coredns" {
  metadata {
    name      = "coredns-pdb"
    namespace = "kube-system"
  }

  spec {
    min_available = "1" # always keep at least 1 CoreDNS pod running

    selector {
      match_labels = {
        k8s-app = "kube-dns" # CoreDNS pods have this label in EKS
      }
    }
  }
}

# Allow all egress from the argocd namespace.
# ArgoCD needs to reach GitHub (HTTPS 443) to pull manifests and the Kubernetes
# API server to apply resources. Rather than enumerate all targets, allow all
# outbound — this is standard practice for GitOps controllers.
resource "kubernetes_network_policy" "argocd_allow_egress" {
  metadata {
    name      = "allow-egress-argocd"
    namespace = "argocd"
  }

  spec {
    pod_selector {} # applies to all pods in argocd namespace

    policy_types = ["Egress"]

    egress {
      # Allow all outbound — ArgoCD needs GitHub, Kubernetes API, Helm registries, etc.
    }
  }

  depends_on = [kubernetes_namespace.standard["argocd"]]
}

# PDB for ArgoCD server — ensures GitOps stays available during maintenance.
resource "kubernetes_pod_disruption_budget_v1" "argocd_server" {
  metadata {
    name      = "argocd-server-pdb"
    namespace = "argocd"
  }

  spec {
    min_available = "1"

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "argocd-server"
      }
    }
  }

  depends_on = [kubernetes_namespace.standard["argocd"]]
}
