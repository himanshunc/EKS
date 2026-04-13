locals {
  # Namespaces that get default LimitRange and NetworkPolicy applied
  managed_namespaces = toset(concat(["default", "kube-system", "monitoring", "logging", "argocd"], var.extra_namespaces))
}
