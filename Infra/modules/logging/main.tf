# ─────────────────────────────────────────────────────────────────────────────
# Logging Module — Step 12
# Ships container logs to CloudWatch using FluentBit.
# Also enables Container Insights for enhanced pod-level metrics.
#
# Log flow:
#   Container stdout/stderr → FluentBit (DaemonSet on every node)
#       → CloudWatch Log Group: /aws/eks/{cluster_name}/containers
#           → Viewable in AMG via CloudWatch data source
# ─────────────────────────────────────────────────────────────────────────────

# ─── CloudWatch Log Group ─────────────────────────────────────────────────

# Log group for all container logs from this cluster.
# FluentBit writes logs here. AMG queries it via the CloudWatch data source.
resource "aws_cloudwatch_log_group" "containers" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days # keep logs for this many days, then auto-delete

  tags = merge(var.tags, {
    Name = local.log_group_name
  })
}

# ─── Container Insights — EKS Add-on ─────────────────────────────────────

# Container Insights add-on — installs the CloudWatch agent as a DaemonSet.
# Provides enhanced pod-level metrics in CloudWatch:
#   - CPU and memory per pod, per container
#   - Network I/O, disk I/O per node
#   - Cluster-level aggregations
# These metrics are also available in AMG via the CloudWatch data source.
resource "aws_eks_addon" "container_insights" {
  count = var.enable_container_insights ? 1 : 0

  cluster_name                = var.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_update = "OVERWRITE"
}

# ─── FluentBit — Container Log Shipper ───────────────────────────────────

# FluentBit runs as a DaemonSet (one pod per node) and tails all container logs.
# Forwards logs to CloudWatch using the node IAM role (CloudWatchAgentServerPolicy).
resource "helm_release" "fluent_bit" {
  name       = "fluent-bit"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  namespace  = "logging"
  version    = "0.46.7"

  wait    = true
  timeout = 300

  values = [
    yamlencode({
      # DaemonSet — runs one FluentBit pod per node to collect logs
      kind = "DaemonSet"

      # Service account — uses node IAM role (CloudWatchAgentServerPolicy already attached)
      serviceAccount = {
        create = true
        name   = "fluent-bit"
      }

      # FluentBit configuration
      config = {
        # Input — tail all container logs from the node's /var/log/containers path
        inputs = <<-EOF
          [INPUT]
              Name              tail
              Tag               kube.*
              Path              /var/log/containers/*.log
              multiline.parser  docker, cri
              Refresh_Interval  5
              Mem_Buf_Limit     5MB
              Skip_Long_Lines   On
        EOF

        # Filter — enrich log records with Kubernetes metadata (namespace, pod name, labels)
        filters = <<-EOF
          [FILTER]
              Name                kubernetes
              Match               kube.*
              Kube_URL            https://kubernetes.default.svc:443
              Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
              Kube_Tag_Prefix     kube.var.log.containers.
              Merge_Log           On
              Keep_Log            Off
              K8S-Logging.Parser  On
              K8S-Logging.Exclude On
        EOF

        # Output — ship to CloudWatch log group
        outputs = <<-EOF
          [OUTPUT]
              Name                cloudwatch_logs
              Match               kube.*
              region              ${var.aws_region}
              log_group_name      ${local.log_group_name}
              log_stream_prefix   fluent-bit-
              auto_create_group   false
              extra_user_agent    container-insights
        EOF
      }

      # Resource limits — FluentBit is lightweight but runs on every node
      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "200m", memory = "256Mi" }
      }

      # Tolerations — run on all nodes including tainted ones (e.g. Spot nodes)
      tolerations = [
        { operator = "Exists" }
      ]
    })
  ]

  depends_on = [aws_cloudwatch_log_group.containers]
}
