locals {
  name_prefix    = "${var.project_name}-${var.environment}"
  log_group_name = "/aws/eks/${var.cluster_name}/containers"
}
