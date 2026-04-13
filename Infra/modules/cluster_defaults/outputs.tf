output "namespace_names" {
  description = "Names of the standard namespaces created by this module"
  value       = [for ns in kubernetes_namespace.standard : ns.metadata[0].name]
}
