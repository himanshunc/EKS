variable "extra_namespaces" {
  description = "Additional namespaces to create and apply LimitRange + NetworkPolicy to (beyond the built-in standard set)"
  type        = list(string)
  default     = []
}
