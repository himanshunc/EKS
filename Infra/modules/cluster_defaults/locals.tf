locals {
  # Namespaces that get default LimitRange and NetworkPolicy applied
  # "argocd" is intentionally excluded — the argocd module owns that namespace.
  # Keeping it here would cause the namespace to get stuck in Terminating on destroy
  # because ArgoCD Application finalizers outlive the ArgoCD controller.
  managed_namespaces = toset(concat(["default", "kube-system", "monitoring", "logging"], var.extra_namespaces))
}
