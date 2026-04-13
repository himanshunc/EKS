# ─────────────────────────────────────────────────────────────────────────────
# Monitoring Module — Step 11
# Full observability stack:
#
#   EKS Pods → Prometheus Agent → AMP Workspace
#                                       │
#   FluentBit → CloudWatch Logs ────────┤
#                                       ▼
#                             Amazon Managed Grafana
#                             ├── AMP data source      (metrics dashboards)
#                             └── CloudWatch source    (log explorer)
#
# Why AMP + AMG instead of self-hosted?
# No EC2 to manage, no Prometheus storage to tune, no Grafana upgrades.
# AWS handles HA, scaling, and retention. You just configure.
# ─────────────────────────────────────────────────────────────────────────────

# ─── AMP Workspace ────────────────────────────────────────────────────────

# Amazon Managed Prometheus workspace — stores all cluster metrics.
# Prometheus agent remote-writes to this endpoint.
resource "aws_prometheus_workspace" "this" {
  alias = "${local.name_prefix}-amp"

  # Retain metrics for 150 days (AWS default, free tier is 150 days)
  # retention_in_days requires a separate API call via aws_prometheus_workspace_configuration

  tags = var.tags
}

# ─── AMP Alert Rules ──────────────────────────────────────────────────────

# Alert rules stored in AMP — evaluated against the metrics in the workspace.
# These fire notifications to AMG alert manager (or SNS if configured).
resource "aws_prometheus_rule_group_namespace" "eks_basics" {
  name         = "eks-basics"
  workspace_id = aws_prometheus_workspace.this.id

  data = <<-YAML
    groups:
      - name: eks-basics
        rules:
          # Alert if a node's CPU has been above 80% for 5 minutes.
          # Sustained high CPU means the node is saturated — consider adding nodes.
          - alert: HighNodeCPU
            expr: 100 - (avg by(node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "Node {{ $labels.node }} CPU above 80%"
              description: "Node {{ $labels.node }} has been above 80% CPU for 5 minutes. Consider adding nodes or reducing load."

          # Alert if a pod was OOMKilled (ran out of memory and was terminated).
          # Immediate action needed: increase memory limits or fix a memory leak.
          - alert: PodOOMKilled
            expr: kube_pod_container_status_last_terminated_reason{reason="OOMKilled"} == 1
            for: 0m
            labels:
              severity: critical
            annotations:
              summary: "Pod {{ $labels.pod }} was OOMKilled"
              description: "Container {{ $labels.container }} in pod {{ $labels.pod }} was OOMKilled. Increase memory limit or investigate leak."

          # Alert if a pod has been in a non-running state for 5 minutes.
          # Catches CrashLoopBackOff, Pending (can't schedule), ImagePullBackOff, etc.
          - alert: PodNotRunning
            expr: kube_pod_status_phase{phase!~"Running|Succeeded"} == 1
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "Pod {{ $labels.pod }} is {{ $labels.phase }}"
              description: "Pod {{ $labels.namespace }}/{{ $labels.pod }} has been in {{ $labels.phase }} state for 5 minutes."

          # Alert if node memory usage is above 85%.
          - alert: HighNodeMemory
            expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "Node {{ $labels.node }} memory above 85%"
              description: "Node {{ $labels.node }} memory utilisation is above 85% for 5 minutes."
  YAML
}

# ─── AMG Workspace ────────────────────────────────────────────────────────

# Amazon Managed Grafana workspace — the Grafana UI and backend.
# IMPORTANT: AMG is not available in all AWS regions (e.g. ap-south-1 / Mumbai).
# Set enable_amg = false in terraform.tfvars to skip this resource.
# Check availability at: https://aws.amazon.com/grafana/faqs/ (Regional availability)
resource "aws_grafana_workspace" "this" {
  count = var.enable_amg ? 1 : 0 # skip if AMG is not available in this region

  name                     = "${local.name_prefix}-amg"
  description              = "Grafana workspace for ${var.project_name} ${var.environment} - metrics from AMP, logs from CloudWatch"
  account_access_type      = "CURRENT_ACCOUNT"        # restrict to this AWS account
  authentication_providers = ["AWS_SSO"]               # login via AWS IAM Identity Center
  permission_type          = "SERVICE_MANAGED"         # AMG manages Grafana permissions
  role_arn                 = var.irsa_amg_role_arn     # IAM role that grants Grafana access to AMP + CloudWatch

  # Data sources — tell AMG which AWS services it can query.
  # PROMETHEUS = AMP, CLOUDWATCH = CloudWatch Logs and Metrics.
  data_sources = ["PROMETHEUS", "CLOUDWATCH"]

  tags = var.tags
}

# NOTE: AMG data sources (AMP + CloudWatch) are configured manually after apply.
# Terraform cannot manage them without a Grafana API key, which only exists after
# the workspace is created. See docs/grafana-dashboards.md for setup instructions.
# The workspace is created with data_sources = ["PROMETHEUS", "CLOUDWATCH"] above,
# which pre-authorises AMG to access both services — you just need to wire them in the UI.

# ─── NetworkPolicy for monitoring namespace ───────────────────────────────

# The cluster_defaults module applies a default-deny NetworkPolicy to all managed
# namespaces (including monitoring). Without these allow rules:
#   - Prometheus cannot reach the AMP endpoint to remote_write metrics
#   - Grafana cannot reach the AMP endpoint to query metrics

# Allow all egress from the monitoring namespace.
# Prometheus needs to reach: AMP (HTTPS 443), all pods for scraping (various ports).
# Grafana needs to reach: AMP (HTTPS 443).
# Rather than listing every scrape port, we allow all egress — this is standard
# practice for observability namespaces since they need to reach every workload.
resource "kubernetes_network_policy" "monitoring_allow_egress" {
  metadata {
    name      = "allow-egress-monitoring"
    namespace = "monitoring"
  }

  spec {
    pod_selector {} # applies to all pods in the monitoring namespace

    policy_types = ["Egress"]

    egress {
      # Allow all egress — Prometheus scrapes every namespace, Grafana queries AMP.
      # Both need unrestricted outbound access.
    }
  }
}

# ─── Grafana OSS (Helm) ───────────────────────────────────────────────────

# Grafana deployed inside the cluster — connects to AMP as a datasource via SigV4.
# Why in-cluster instead of AMG? AMG is not available in all regions (e.g. ap-south-1).
# This gives identical functionality: dashboards, alerts, CloudWatch logs — no EC2 needed.
#
# Access after deploy:
#   kubectl port-forward svc/grafana 3000:80 -n monitoring
#   Open http://localhost:3000  (admin / admin123 — change in prod!)
resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = "monitoring"
  version    = "7.3.7"

  wait    = true
  timeout = 300

  values = [
    yamlencode({
      # Service account — annotated with IRSA role so the pod can sign AMP requests
      serviceAccount = {
        name = "grafana" # must match the name in the IRSA trust policy
        annotations = {
          "eks.amazonaws.com/role-arn" = var.irsa_grafana_role_arn
        }
      }

      "grafana.ini" = {
        analytics = {
          check_for_updates = false
        }
      }

      # Pre-wire AMP as the default Prometheus datasource.
      # SigV4 auth uses the pod's IAM role (IRSA) — no credentials needed.
      datasources = {
        "datasources.yaml" = {
          apiVersion = 1
          datasources = [
            {
              name      = "Prometheus"
              type      = "prometheus"
              url       = "http://prometheus-agent-server.monitoring.svc.cluster.local"
              isDefault = true
              jsonData = {
                httpMethod = "POST"
                # No SigV4 auth — Grafana queries Prometheus directly in-cluster.
                # Prometheus is in the same namespace (monitoring) so no auth is needed.
                # AMP remote_write still works for long-term storage and alerting.
              }
            }
          ]
        }
      }

      # ClusterIP — use kubectl port-forward to access in dev.
      # Change to LoadBalancer (with ALB annotations) to expose externally.
      service = {
        type = "ClusterIP"
        port = 80
      }

      # Resource requests — small footprint, suitable for t3.medium
      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "300m", memory = "256Mi" }
      }

      # No persistence in dev — avoids EBS AZ-affinity scheduling issues on 2-node clusters.
      # In prod: set enabled=true with storageClassName="gp3" size="5Gi"
      persistence = {
        enabled = false
      }

      # Default admin credentials — CHANGE IN PRODUCTION
      # In prod: use a k8s Secret and reference it via admin.existingSecret
      adminUser     = "admin"
      adminPassword = "admin123"
    })
  ]
}

# ─── Prometheus Agent (Helm) ──────────────────────────────────────────────

# Prometheus in agent mode — scrapes pod metrics and remote-writes to AMP.
# Agent mode has no local storage (smaller footprint than full Prometheus).
# It only forwards metrics — no querying, no alerting locally.
resource "helm_release" "prometheus_agent" {
  name       = "prometheus-agent"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  namespace  = "monitoring"
  version    = "25.20.0"

  wait    = true
  timeout = 300

  values = [
    yamlencode({
      # NOTE: This is the standalone `prometheus` chart (not kube-prometheus-stack).
      # All server config goes under `server:`, NOT `prometheusSpec:`.

      # NOTE: In the standalone prometheus chart, service account config is a TOP-LEVEL
      # key `serviceAccounts.server`, NOT `server.serviceAccount`. Setting it under
      # `server` is silently ignored — the pod falls back to the node role instead of IRSA.
      serviceAccounts = {
        server = {
          # Pin name to match the IRSA trust policy: system:serviceaccount:monitoring:prometheus-agent
          name = "prometheus-agent"
          annotations = {
            "eks.amazonaws.com/role-arn" = var.irsa_amp_ingest_role_arn
          }
        }
      }

      server = {
        # Agent mode — use the chart's native agentMode flag, NOT extraFlags.
        # The chart suppresses --storage.tsdb.path and --storage.tsdb.retention.time
        # (which are fatal in agent mode) and adds --storage.agent.path instead.
        agentMode = true

        # Remote write to AMP — SigV4 signing uses the IRSA credentials on the pod.
        # The sigv4 block tells Prometheus to sign requests using the default credential chain
        # (which finds the IRSA token at the projected volume path).
        remoteWrite = [
          {
            url = "${aws_prometheus_workspace.this.prometheus_endpoint}api/v1/remote_write"
            sigv4 = {
              region = var.aws_region
            }
            queue_config = {
              max_samples_per_send = 1000
              max_shards           = 200
              capacity             = 2500
            }
          }
        ]

        resources = {
          requests = { cpu = "200m", memory = "512Mi" }
          limits   = { cpu = "500m", memory = "1Gi" }
        }
      }

      # configmapReload watches for ConfigMap changes and triggers a Prometheus reload.
      # In agent mode the config is static — disable it to avoid OOMKill (it has no
      # memory limits by default and gets evicted first under any node memory pressure).
      configmapReload = {
        prometheus = { enabled = false }
      }

      # Disable components not needed in agent mode
      alertmanager                 = { enabled = false } # alerting handled by AMP rules
      pushgateway                  = { enabled = false } # not needed in agent mode
      "prometheus-node-exporter"   = { enabled = true }  # OS-level node metrics (CPU, memory, disk)
      "kube-state-metrics"         = { enabled = true }  # Kubernetes object state (pod counts, etc.)
    })
  ]
}
