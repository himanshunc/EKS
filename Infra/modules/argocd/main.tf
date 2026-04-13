# ─────────────────────────────────────────────────────────────────────────────
# ArgoCD Module — Step 10
# Deploys ArgoCD via Helm into the "argocd" namespace.
#
# ArgoCD implements GitOps: it watches a Git repository and automatically
# applies any changes to the cluster. Git becomes the single source of truth.
#
# Access: ArgoCD server runs as ClusterIP. Expose it via an ALB Ingress
# (examples/argocd-app.yaml shows the pattern) or use kubectl port-forward.
# ─────────────────────────────────────────────────────────────────────────────

# ArgoCD — GitOps continuous delivery tool for Kubernetes.
# chart = "argo-cd" is the official Helm chart maintained by the ArgoCD project.
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"
  version    = "6.7.3"

  # Wait for all pods to be ready before marking the release as deployed
  wait    = true
  timeout = 600 # 10 minutes — ArgoCD takes a moment to pull images and start

  # Server service type = ClusterIP.
  # Expose via ALB Ingress (preferred) or kubectl port-forward (quick access).
  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  # Insecure mode — lets the ALB terminate TLS instead of ArgoCD.
  # The ALB handles the cert; ArgoCD serves plain HTTP internally.
  set {
    name  = "server.extraArgs[0]"
    value = "--insecure"
  }

  # Resource requests — sized for dev. Increase in prod.
  set {
    name  = "server.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "server.resources.requests.memory"
    value = "128Mi"
  }
  set {
    name  = "server.resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "server.resources.limits.memory"
    value = "512Mi"
  }

  # Enable metrics endpoint — Prometheus agent will scrape this
  set {
    name  = "server.metrics.enabled"
    value = "true"
  }

  # ALB Ingress — exposes ArgoCD UI via an internet-facing AWS Application Load Balancer.
  # The ALB controller (already running) provisions the ALB automatically from this Ingress.
  # Access URL: use the ALB DNS from `kubectl get ingress -n argocd` after apply.
  set {
    name  = "server.ingress.enabled"
    value = "true"
  }

  set {
    name  = "server.ingress.ingressClassName"
    value = "alb"
  }

  # internet-facing = public ALB (accessible from your laptop)
  set {
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/scheme"
    value = "internet-facing"
  }

  # ip target type — routes directly to pod IPs (required for ALB with EKS)
  set {
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/target-type"
    value = "ip"
  }

  # HTTP only — no certificate needed for dev
  set {
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/listen-ports"
    value = "[{\"HTTP\": 80}]"
  }

  # Clear the default hostname so the ALB accepts requests on its auto-generated
  # DNS name without a host-header condition. global.domain drives the default
  # host in chart v6+; setting it empty + hosts=[] produces a catch-all rule.
  set {
    name  = "global.domain"
    value = ""
  }

  values = [
    yamlencode({
      server = {
        ingress = {
          hosts = []
        }
      }
    })
  ]

  # Repo server — handles Git operations (clone, diff, render manifests)
  set {
    name  = "repoServer.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "repoServer.resources.requests.memory"
    value = "128Mi"
  }
}
