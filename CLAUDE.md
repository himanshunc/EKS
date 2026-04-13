# 🧠 CLAUDE.md — AWS EKS Terraform Infrastructure (Learning Project)

> This file is automatically read by Claude Code at the start of every session.
> It defines the project architecture, conventions, constraints, and goals.
> When in doubt — keep it simple, keep it commented, keep it learnable.

---

## 📌 Project Overview

This is a **simple, readable Terraform infrastructure project** for deploying
**AWS EKS (Elastic Kubernetes Service)** on AWS. Built for **learning purposes** —
every file is intentionally straightforward, heavily commented, and easy to follow.

**Primary Goals:**
- Deploy an EKS cluster (public + private endpoint, parameterised)
- Simple, readable code — no over-engineering, no deep abstractions
- Cost optimisation: Spot instances, gp3 volumes, ECR lifecycle policies, VPC endpoints
- GitOps via ArgoCD with a sample app manifest
- Full observability: metrics AND logs in **Amazon Managed Grafana (AMG)**
  - Metrics: Prometheus agent → AMP → AMG (with pre-built dashboards)
  - Logs: FluentBit → CloudWatch → AMG (CloudWatch data source)
  - Alerts: AMP alerting rules for CPU, memory, OOMKilled
- Security best practices: KMS rotation, audit logs, VPC endpoints, network policies
- Reliability: PDB, resource limits, Node Termination Handler
- CI/CD: GitHub Actions for Terraform plan/apply + branch protection
- Everything destroyable cleanly in reverse dependency order

**Simplicity Rules:**
- Prefer flat, readable code over clever abstractions
- Every file understandable by a junior DevOps engineer
- Inline comments on every resource block and non-obvious attribute
- `.tfvars` files — comment above every single variable
- No module deeper than 2 levels of nesting

---

## 🗂️ Folder Structure

```
eks-terraform/                          ← root of the Git repo
│
├── .github/
│   ├── workflows/
│   │   ├── terraform-plan.yml          # PR check: fmt + validate + plan
│   │   └── terraform-apply.yml         # Push to main: apply
│   └── pull_request_template.md        # PR checklist for infra changes
│
├── infra/
│   ├── bootstrap/                      # Step 0: S3 + DynamoDB for Terraform state
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   ├── providers.tf
│   │   └── versions.tf
│   │
│   ├── modules/                        # One module = one concern
│   │   ├── vpc/                        # Step 1: VPC, subnets, IGW, NAT, route tables,
│   │   │                               #         VPC endpoints (S3, ECR, STS, EC2)
│   │   ├── security_groups/            # Step 2: EKS cluster SG + node SG
│   │   ├── iam/                        # Step 3: All IAM roles + IRSA roles
│   │   ├── kms/                        # Step 4: KMS key for EKS secrets encryption
│   │   │                               #         (key rotation enabled)
│   │   ├── eks/                        # Step 5: EKS cluster + OIDC + managed add-ons
│   │   │                               #         + audit logging → CloudWatch
│   │   ├── node_groups/                # Step 6: Spot + on-demand node groups
│   │   ├── ecr/                        # Step 7: ECR repos + lifecycle policies
│   │   ├── cluster_defaults/           # Step 8: PodDisruptionBudgets + LimitRanges
│   │   │                               #         + default NetworkPolicy (deny-all)
│   │   ├── helm_addons/                # Step 9: ALB controller, metrics-server,
│   │   │                               #         cluster-autoscaler, EBS CSI,
│   │   │                               #         Node Termination Handler
│   │   ├── argocd/                     # Step 10: ArgoCD via Helm
│   │   ├── monitoring/                 # Step 11: AMP + Prometheus agent + AMG
│   │   │                               #          + AMP alert rules
│   │   │                               #          + Grafana dashboard provisioning
│   │   └── logging/                    # Step 12: FluentBit → CloudWatch
│   │                                   #          + Container Insights
│   │
│   ├── environments/
│   │   ├── dev/
│   │   │   ├── main.tf                 # Wires all modules + explicit depends_on
│   │   │   ├── variables.tf
│   │   │   ├── terraform.tfvars        # Every variable has a comment
│   │   │   └── outputs.tf
│   │   └── prod/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── terraform.tfvars
│   │       └── outputs.tf
│   │
│   └── global/
│       ├── backend.tf                  # S3 remote state config
│       ├── providers.tf                # All provider configs
│       └── versions.tf
│
├── examples/
│   └── argocd-app.yaml                 # Sample ArgoCD Application manifest
│
├── docs/
│   ├── architecture.md                 # Architecture decisions + diagrams
│   ├── destroy-guide.md                # Step-by-step ordered destroy instructions
│   ├── grafana-dashboards.md           # Dashboard IDs + import instructions
│   └── branching-strategy.md          # Git branching and PR workflow
│
├── .gitignore                          # Ignores .terraform/, *.tfstate, *.tfvars.local
├── .editorconfig                       # Consistent formatting across editors
├── .pre-commit-config.yaml             # terraform fmt, validate, tflint hooks
├── CLAUDE.md                           # This file
└── README.md                           # Human-readable project overview
```

---

## 📦 Module File Rules (MANDATORY)

Every module under `modules/` MUST contain:

- `main.tf` — resource definitions, comment above **every** resource block
- `variables.tf` — all variables with `description` and `type`
- `outputs.tf` — all outputs with `description`
- `locals.tf` — computed names only (omit if empty)

**Never create a module without all required files.**

---

## 🔧 Coding Conventions

### Naming
- `snake_case` everywhere
- Format: `{project}-{environment}-{component}` (e.g. `myapp-dev-eks-cluster`)
- All names built in `locals.tf`, never inline

### Tagging (ALL resources)
```hcl
tags = {
  Project     = var.project_name
  Environment = var.environment
  ManagedBy   = "Terraform"
  Owner       = var.owner
}
```

### Variable Rules
- `description` and `type` on every variable
- `sensitive = true` on secrets
- `default` only when a safe fallback exists
- No hardcoded values in `main.tf`

### Output Rules
- Every output has a `description`
- Export everything another module might need

### Comment Rules
```hcl
# KMS Key — used to encrypt EKS secrets at rest.
# enable_key_rotation = true is a security best practice and AWS recommendation.
resource "aws_kms_key" "eks" {
  enable_key_rotation = true   # rotates the key material annually, automatically
  ...
}
```

### .tfvars Comment Rules (MANDATORY)
Every variable in `.tfvars` must have a comment explaining what it controls,
allowed values, and when you'd change it. No uncommented variables — ever.

---

## 🌐 Networking — `vpc` Module

All networking + VPC endpoints in one module.

| Component        | Detail                                                  |
|------------------|---------------------------------------------------------|
| VPC CIDR         | `10.0.0.0/16`                                           |
| Public subnets   | 2 AZs — `10.0.1.0/24`, `10.0.2.0/24`                   |
| Private subnets  | 2 AZs — `10.0.3.0/24`, `10.0.4.0/24`                   |
| NAT Gateway      | Single (dev) / per-AZ (prod) via `single_nat_gateway`  |
| Internet Gateway | Attached                                                |
| VPC Endpoints    | S3 (Gateway), ECR API, ECR DKR, STS, EC2 (Interface)  |

**Why VPC endpoints?**
Without them, node image pulls from ECR and AWS API calls leave the VPC via the
NAT gateway — you pay NAT data charges and add latency. With VPC endpoints, that
traffic stays on the AWS private network — free and faster.

**Subnet tags for Kubernetes:**
```hcl
# Public — internet-facing ALBs
"kubernetes.io/role/elb" = "1"

# Private — internal ALBs + EKS nodes
"kubernetes.io/role/internal-elb"           = "1"
"kubernetes.io/cluster/${var.cluster_name}" = "owned"
```

---

## 🔐 Security — Best Practices Applied

### KMS Module (`modules/kms/`)
```hcl
# KMS Key for EKS secrets encryption
resource "aws_kms_key" "eks" {
  description             = "EKS secrets encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true   # ← MANDATORY: annual automatic rotation
}
```

### IAM Roles
| Role                      | Purpose                                              |
|---------------------------|------------------------------------------------------|
| `eks-cluster-role`        | EKS control plane — `AmazonEKSClusterPolicy`        |
| `eks-node-role`           | Worker nodes — EC2, EKS, ECR, CloudWatch policies   |
| `irsa-alb-controller`     | ALB Controller (includes waf-regional + wafv2)      |
| `irsa-cluster-autoscaler` | Cluster Autoscaler                                  |
| `irsa-ebs-csi-driver`     | EBS CSI Driver                                      |
| `irsa-amp-ingest`         | Prometheus agent → AMP remote write                 |
| `irsa-amg`                | AMG → AMP query + CloudWatch Logs read              |

### ALB Controller IRSA — Required Permissions
The ALB controller needs BOTH `wafv2` and `waf-regional` permissions, plus
listener/listener-rule ARNs in the `AddTags` statement. Missing any of these
causes `AccessDenied` during ALB provisioning.

**AddTags resource list must include listeners:**
```hcl
Resource = [
  "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
  "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
  "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
  "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",     # ← required
  "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",     # ← required
  "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",# ← required
  "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*" # ← required
]
```

**WAF permissions must include both v1 (regional) and v2:**
```hcl
Action = [
  "wafv2:GetWebACL", "wafv2:GetWebACLForResource",
  "wafv2:AssociateWebACL", "wafv2:DisassociateWebACL",
  "waf-regional:GetWebACLForResource", "waf-regional:GetWebACL",  # ← required
  "waf-regional:AssociateWebACL", "waf-regional:DisassociateWebACL",
  ...
]
```

### Principles
- Least privilege — no `*` actions unless required
- IRSA only — no static credentials anywhere
- Audit logs shipped to CloudWatch (see EKS spec)

---

## ☸️ EKS Cluster — `eks` Module

| Setting                  | Value                                                      |
|--------------------------|------------------------------------------------------------|
| Endpoint public access   | `var.eks_endpoint_public_access` (default: `true`)        |
| Endpoint private access  | Always `true`                                              |
| Public access CIDRs      | `var.eks_public_access_cidrs` (default: `["0.0.0.0/0"]`) |
| Kubernetes version       | `var.kubernetes_version` (default: `"1.29"`)              |
| Secrets encryption       | KMS key from `kms` module                                  |
| OIDC provider            | Enabled — required for IRSA                               |
| Managed add-ons          | `coredns`, `kube-proxy`, `vpc-cni`                        |
| **Audit logging**        | `api`, `audit`, `authenticator` → CloudWatch              |

**Audit log setup in `main.tf`:**
```hcl
# EKS control plane logging — sends API, audit, and auth logs to CloudWatch.
# "audit" is the most important — records every kubectl command and API call.
resource "aws_eks_cluster" "this" {
  enabled_cluster_log_types = ["api", "audit", "authenticator"]
  ...
}
```

---

## 💻 Node Groups — `node_groups` Module

| Setting           | Value                          |
|-------------------|--------------------------------|
| Type              | Managed Node Groups            |
| Primary           | SPOT                           |
| Fallback          | On-Demand                      |
| Instance types    | `t3.medium`, `t3.large`        |
| AMI               | `AL2_x86_64`                   |
| Volume type       | `gp3`                          |
| Volume size       | `50 GB`                        |
| Min / Desired / Max | `1` / `2` / `4`             |

---

## 📦 ECR — `ecr` Module

- One repo per app (list variable)
- Image scanning on push
- Lifecycle: keep last 10 images, expire untagged after 7 days

---

## 🛡️ Cluster Defaults — `cluster_defaults` Module

This module applies sane Kubernetes-level defaults immediately after the cluster
and nodes are ready. It is the most educational module for learning Kubernetes
resource management.

### Pod Disruption Budgets (PDB)
```yaml
# PDB ensures at least 1 replica is always running during node drains.
# Without this, a rolling node upgrade could take down ALL pods simultaneously.
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: example-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: example
```
Create PDBs for: `kube-dns`, `coredns`, `argocd-server`, and any app you deploy.

### LimitRange (per namespace)
```yaml
# LimitRange sets default CPU/memory for pods that don't specify their own.
# Without this, a single runaway pod can consume all node resources.
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
spec:
  limits:
  - type: Container
    default:
      cpu: "500m"
      memory: "256Mi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    max:
      cpu: "2"
      memory: "1Gi"
```

### Default NetworkPolicy (deny-all)
```yaml
# Deny all ingress/egress by default — pods must explicitly allow traffic.
# This is the Kubernetes equivalent of a default-deny firewall rule.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```
Apply per namespace, then add explicit allow policies for each service.

---

## ⚙️ Helm Addons — `helm_addons` Module

| Addon                        | Chart                          | Namespace     |
|------------------------------|--------------------------------|---------------|
| AWS Load Balancer Controller | `aws-load-balancer-controller` | `kube-system` |
| Metrics Server               | `metrics-server`               | `kube-system` |
| Cluster Autoscaler           | `cluster-autoscaler`           | `kube-system` |
| EBS CSI Driver               | `aws-ebs-csi-driver`           | `kube-system` |
| **Node Termination Handler** | `aws-node-termination-handler` | `kube-system` |

### Node Termination Handler
Listens for AWS Spot interruption notices (2-minute warning) and gracefully
drains the node before AWS reclaims it. Without this, pods are killed abruptly.
```hcl
# aws-node-termination-handler — listens for Spot interruption signals via SQS
# and drains the node gracefully before AWS terminates the instance.
resource "helm_release" "nth" {
  name       = "aws-node-termination-handler"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-node-termination-handler"
  namespace  = "kube-system"
}
```

### ALB Controller — Webhook Race Condition (CRITICAL)
Terraform deploys all Helm releases in parallel by default. If the ALB webhook
is not ready when other charts install, pods fail admission. Fix:
```hcl
# ALB controller must be fully ready before other charts install
resource "helm_release" "alb_controller" {
  wait    = true   # wait for all pods ready before marking deployed
  timeout = 300
}

# Every other helm_release must depend on ALB controller
resource "helm_release" "cluster_autoscaler" {
  depends_on = [helm_release.alb_controller]
}
```

### Cluster Autoscaler — Service Account Name (CRITICAL)
The default chart SA name is `cluster-autoscaler-aws-cluster-autoscaler` but the
IRSA trust policy expects `cluster-autoscaler`. Pin the name explicitly:
```hcl
set {
  name  = "rbac.serviceAccount.name"
  value = "cluster-autoscaler"
}
```

---

## 🚀 ArgoCD — `argocd` Module + Sample Manifest

| Setting      | Value                                            |
|--------------|--------------------------------------------------|
| Helm chart   | `argo-cd`                                        |
| Namespace    | `argocd`                                         |
| Service type | `ClusterIP` (expose via ALB Ingress)             |
| Purpose      | GitOps — syncs Kubernetes manifests from Git     |

### ALB Ingress — Catch-all Host (CRITICAL)
ArgoCD chart v6+ uses `global.domain` (default: `argocd.example.com`) as the
ingress hostname. Without clearing it, the ALB creates a host-header rule that
only matches `argocd.example.com` — requests via the ALB DNS name return 404.

Fix: set `global.domain = ""` AND set `server.ingress.hosts = []` via a values block.
Using `set { server.ingress.hosts[0] = "" }` alone does NOT work — the chart
ignores the empty string and falls back to the global domain default.

```hcl
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
```

**Sample `examples/argocd-app.yaml`** (committed to repo, educational):
```yaml
# ArgoCD Application — tells ArgoCD to watch a Git repo and sync to EKS.
# This is the core GitOps pattern: Git is the source of truth.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/your-app-repo
    targetRevision: main          # branch/tag to sync from
    path: k8s/                    # folder containing manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true                 # delete resources removed from Git
      selfHeal: true              # revert manual kubectl changes
```

---

## 📊 Monitoring — `monitoring` Module

### Full Architecture
```
EKS Pods → Prometheus Agent → AMP Workspace
                │                    │
                │             FluentBit → CloudWatch Logs
                ▼
     In-cluster Grafana OSS (Helm)
     └── Prometheus datasource (in-cluster, no SigV4 needed)

     Amazon Managed Grafana (optional — not available in ap-south-1)
     ├── AMP data source      (metrics dashboards)
     └── CloudWatch source    (log explorer)
```

### AMG Availability
AMG is NOT available in `ap-south-1` (Mumbai). Use `enable_amg = false` and
deploy Grafana OSS in-cluster instead. Set `enable_amg = true` only in supported
regions (us-east-1, eu-west-1, etc.).

### Resources
| Resource                     | Type                       | Purpose                            |
|------------------------------|----------------------------|------------------------------------|
| AMP Workspace                | `aws_prometheus_workspace` | Stores metrics                     |
| IRSA — Prometheus agent      | `aws_iam_role`             | Pod → AMP remote_write             |
| Prometheus agent             | Helm (`prometheus` chart)  | Scrape + forward to AMP            |
| Grafana OSS                  | Helm (`grafana` chart)     | In-cluster dashboards              |
| AMP alert rules              | `aws_prometheus_rule_group_namespace` | CPU, memory, OOMKill alerts |
| AMG Workspace                | `aws_grafana_workspace`    | Grafana UI (optional)              |
| AMG IAM role                 | `aws_iam_role`             | AMG → AMP + CloudWatch             |

### Prometheus Helm Chart — Critical Notes
Use the standalone `prometheus` chart (NOT `kube-prometheus-stack`).

**Wrong key (kube-prometheus-stack):**
```yaml
prometheusSpec:    ← WRONG for standalone chart
  remoteWrite: ...
```

**Correct key (standalone prometheus chart):**
```yaml
server:            ← correct
  agentMode: true
  remoteWrite: ...
```

**Service account is TOP-LEVEL, not under `server`:**
```hcl
# WRONG — silently ignored, pod falls back to node role instead of IRSA
server = { serviceAccount = { name = "prometheus-agent" } }

# CORRECT — top-level key
serviceAccounts = {
  server = {
    name = "prometheus-agent"   # must match IRSA trust policy
    annotations = { "eks.amazonaws.com/role-arn" = var.irsa_amp_ingest_role_arn }
  }
}
```

**Disable configmapReload in agent mode** — it has no memory limits and gets
OOMKilled first under any node memory pressure:
```hcl
configmapReload = {
  prometheus = { enabled = false }
}
```

**Memory:** Set `server.resources.limits.memory = "1Gi"` minimum for agent mode.

### Grafana OSS — Datasource (No SigV4 Needed)
Grafana 11 + IRSA SigV4 is unreliable (missing `AWS_WEB_IDENTITY_TOKEN_FILE`).
Point Grafana directly at in-cluster Prometheus instead of AMP:
```hcl
datasources = {
  "datasources.yaml" = {
    apiVersion = 1
    datasources = [{
      name      = "Prometheus"
      type      = "prometheus"
      url       = "http://prometheus-agent-server.monitoring.svc.cluster.local"
      isDefault = true
    }]
  }
}
```
Prometheus still remote-writes to AMP for long-term storage and alerts.
Grafana queries Prometheus in-cluster for dashboards — no SigV4 needed.

### Grafana OSS — Persistence
Disable persistence in dev to avoid EBS AZ-affinity scheduling failures:
```hcl
persistence = { enabled = false }
```

### NetworkPolicy — Monitoring Namespace
Default-deny blocks Prometheus → AMP and Grafana → Prometheus egress.
Always add an allow-all-egress policy for the monitoring namespace:
```hcl
resource "kubernetes_network_policy" "monitoring_allow_egress" {
  spec {
    pod_selector {}
    policy_types = ["Egress"]
    egress {}    # allow all egress
  }
}
```

### AMP Alert Rules (add to `monitoring` module)
```yaml
# Basic alerting rules — add to aws_prometheus_rule_group_namespace resource
groups:
  - name: eks-basics
    rules:
      # Alert if a node CPU has been over 80% for 5 minutes
      - alert: HighNodeCPU
        expr: 100 - (avg by(node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Node {{ $labels.node }} CPU above 80%"

      # Alert if a pod was OOMKilled (ran out of memory)
      - alert: PodOOMKilled
        expr: kube_pod_container_status_last_terminated_reason{reason="OOMKilled"} == 1
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "Pod {{ $labels.pod }} was OOMKilled — increase memory limit"

      # Alert if a pod has been in a non-running state for 5 minutes
      - alert: PodNotRunning
        expr: kube_pod_status_phase{phase!~"Running|Succeeded"} == 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Pod {{ $labels.pod }} is {{ $labels.phase }}"
```

### Pre-built Grafana Dashboard IDs
Import these in AMG after setup (Dashboards → Import → enter ID):

| Dashboard | ID | What it shows |
|---|---|---|
| Kubernetes Cluster Overview | `315` | Nodes, namespaces, pod count |
| Kubernetes Namespace Resources | `3119` | CPU/memory per namespace |
| Kubernetes Pod Resources | `6417` | Per-pod CPU, memory, restarts |
| Node Exporter Full | `1860` | Detailed OS-level node metrics |
| EKS CloudWatch Container Insights | built-in | Container Insights in AMG |

See `docs/grafana-dashboards.md` for step-by-step import instructions.

### CloudWatch Container Insights
Enable in the `logging` or `monitoring` module:
```hcl
# Container Insights gives enhanced CloudWatch metrics for EKS:
# pod-level CPU, memory, disk, network — visible in CloudWatch AND in AMG.
resource "aws_eks_addon" "container_insights" {
  cluster_name = var.cluster_name
  addon_name   = "amazon-cloudwatch-observability"
}
```

---

## 📜 Logging — `logging` Module

| Tool       | Destination                                   |
|------------|-----------------------------------------------|
| FluentBit  | Helm → CloudWatch Log Group                   |
| Log group  | `/aws/eks/{cluster_name}/containers`          |
| In Grafana | CloudWatch data source in AMG                 |
| Container Insights | `amazon-cloudwatch-observability` add-on |

Node IAM role has `CloudWatchAgentServerPolicy` attached (in `iam` module).

---

## 🔄 Backend & Providers

**`global/backend.tf`:**
```hcl
terraform {
  backend "s3" {
    bucket         = "<from bootstrap output>"
    key            = "envs/${var.environment}/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "<from bootstrap output>"
    encrypt        = true
  }
}
```

**Required providers:**
```hcl
terraform {
  required_providers {
    aws      = { source = "hashicorp/aws",   version = "~> 5.0"  }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.20" }
    helm     = { source = "hashicorp/helm",  version = "~> 2.10" }
    tls      = { source = "hashicorp/tls",   version = "~> 4.0"  }
    grafana  = { source = "grafana/grafana", version = "~> 2.0"  }
  }
  required_version = ">= 1.6.0"
}
```

---

## 🌍 Region & AZs

- Default region: `ap-south-1` (Mumbai)
- AZs: `ap-south-1a`, `ap-south-1b`
- Never hardcode — always pass as variables

---

## 🧪 terraform.tfvars — dev (Canonical)

```hcl
# ── Project ──────────────────────────────────────────────────────────────────

# Short project name — prefix for all resource names and tags
project_name = "myapp"

# Environment label — affects naming, NAT count, node sizes
# Allowed: "dev" | "staging" | "prod"
environment = "dev"

# Team responsible — shows in resource tags for cost attribution
owner = "devops-team"

# ── AWS ──────────────────────────────────────────────────────────────────────

# AWS region where all resources are created
aws_region = "ap-south-1"

# ── Kubernetes ───────────────────────────────────────────────────────────────

# EKS Kubernetes version — check AWS supported versions before changing
# https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
kubernetes_version = "1.29"

# ── Networking ───────────────────────────────────────────────────────────────

# VPC IP range — all subnets carved from this CIDR
vpc_cidr = "10.0.0.0/16"

# true  = one shared NAT gateway (~$32/month, fine for dev)
# false = one NAT per AZ (~$64/month, required for prod HA)
single_nat_gateway = true

# Enable VPC endpoints for S3, ECR, STS, EC2
# true = traffic stays on AWS network (faster + cheaper than NAT)
# Always true — only disable if debugging connectivity issues
enable_vpc_endpoints = true

# ── EKS Endpoint ─────────────────────────────────────────────────────────────

# true  = kubectl works from your laptop (great for learning)
# false = VPC-only access, need VPN or bastion (use in prod)
eks_endpoint_public_access = true

# Which IPs can reach the public endpoint
# "0.0.0.0/0" = everyone (fine for learning)
# ["x.x.x.x/32"] = your IP only (better practice)
eks_public_access_cidrs = ["0.0.0.0/0"]

# ── Node Groups ──────────────────────────────────────────────────────────────

# EC2 instance types — t3.large minimum for full stack
# t3.medium = 17 max pods/node — NOT enough for ArgoCD + monitoring + system pods
# t3.large  = 35 max pods/node — fits the full stack comfortably
node_instance_types = ["t3.large"]

# Node count: 1 spot + 1 on-demand gives resilience without cost
node_min_size     = 1
node_desired_size = 1
node_max_size     = 2

# ── ECR ──────────────────────────────────────────────────────────────────────

# Container image repositories to create (one per application)
ecr_repositories = ["api", "frontend", "worker"]

# ── Feature Flags ────────────────────────────────────────────────────────────

# Enable CloudWatch Container Insights (enhanced pod-level metrics)
# true is recommended — adds minimal cost, adds a lot of observability
enable_container_insights = true

# Enable Amazon Managed Grafana (AMG)
# false = AMG not available in ap-south-1 — Grafana OSS deployed in-cluster instead
# true  = only set in supported regions (us-east-1, eu-west-1, etc.)
enable_amg = false
```

---

## 🔀 Dependency & Destroy Order

Apply top-to-bottom. Destroy bottom-to-top.
`depends_on` must be explicit in `environments/dev/main.tf`.

```
APPLY ORDER                           DESTROY ORDER (reverse)
══════════════════════════            ═══════════════════════════════
0.  bootstrap    (manual, once)       12. logging
1.  kms                               11. monitoring
2.  vpc                               10. argocd
3.  security_groups                   9.  cluster_defaults
4.  iam                               8.  helm_addons
5.  eks                               7.  ecr
6.  node_groups                       6.  node_groups
7.  ecr          (parallel OK)        5.  eks
8.  cluster_defaults                  4.  iam
9.  helm_addons                       3.  security_groups
10. argocd                            2.  vpc
11. monitoring                        1.  kms
12. logging                           0.  bootstrap (optional)
```

**`depends_on` in `environments/dev/main.tf`:**
```hcl
module "vpc"              { depends_on = [module.kms] }
module "security_groups"  { depends_on = [module.vpc] }
module "iam"              { depends_on = [module.eks] }        # needs OIDC URL
module "eks"              { depends_on = [module.kms, module.security_groups] }
module "node_groups"      { depends_on = [module.eks, module.iam] }
module "cluster_defaults" { depends_on = [module.node_groups] }
module "helm_addons"      { depends_on = [module.cluster_defaults] }
module "argocd"           { depends_on = [module.helm_addons] }
module "monitoring"       { depends_on = [module.helm_addons] }
module "logging"          { depends_on = [module.monitoring] }
```

**Ordered destroy:**
```bash
cd infra/environments/dev
terraform destroy -target=module.logging
terraform destroy -target=module.monitoring
terraform destroy -target=module.argocd
terraform destroy -target=module.cluster_defaults
terraform destroy -target=module.helm_addons
terraform destroy -target=module.ecr
terraform destroy -target=module.node_groups
terraform destroy -target=module.eks
terraform destroy -target=module.iam
terraform destroy -target=module.security_groups
terraform destroy -target=module.vpc
terraform destroy -target=module.kms
# Optional: cd ../../bootstrap && terraform destroy
```

---

## 🌿 Git Branching Strategy

```
main          ← production-ready, protected, requires PR + approval
  │
  └── develop ← integration branch, all features merge here first
        │
        └── feature/vpc-endpoints     ← one branch per module/feature
        └── feature/monitoring-amp
        └── feature/node-termination-handler
        └── fix/kms-key-rotation
```

### Branch Rules
| Branch | Protection | Who merges |
|---|---|---|
| `main` | Required PR, 1 approval, CI must pass, no direct push | Lead / senior |
| `develop` | Required PR, CI must pass | Any team member |
| `feature/*` | No protection | Author |
| `fix/*` | No protection | Author |

### PR Flow
```
feature/* → develop (PR + review) → main (PR + approval + CI green)
```

### GitHub Actions Triggers
- `terraform-plan.yml` — runs on every PR to `develop` or `main`
- `terraform-apply.yml` — runs on push/merge to `main` only

---

## 🔁 GitHub Actions Workflows

### `.github/workflows/terraform-plan.yml`
```yaml
name: Terraform Plan

on:
  pull_request:
    branches: [main, develop]
    paths: ["infra/**"]

jobs:
  plan:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # for OIDC auth to AWS
      contents: read
      pull-requests: write

    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.6.0"

      - name: Configure AWS credentials (OIDC — no static keys)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ap-south-1

      - name: Terraform fmt check
        run: terraform fmt -check -recursive
        working-directory: infra/environments/dev

      - name: Terraform init
        run: terraform init
        working-directory: infra/environments/dev

      - name: Terraform validate
        run: terraform validate
        working-directory: infra/environments/dev

      - name: Terraform plan
        run: terraform plan -out=tfplan
        working-directory: infra/environments/dev

      - name: Post plan to PR
        uses: actions/github-script@v7
        # Posts plan output as a PR comment for review
```

### `.github/workflows/terraform-apply.yml`
```yaml
name: Terraform Apply

on:
  push:
    branches: [main]
    paths: ["infra/**"]

jobs:
  apply:
    runs-on: ubuntu-latest
    environment: production   # requires manual approval in GitHub
    permissions:
      id-token: write
      contents: read

    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ap-south-1
      - run: terraform init
        working-directory: infra/environments/dev
      - run: terraform apply -auto-approve
        working-directory: infra/environments/dev
```

---

## 💰 Cost Optimisation

- ✅ Spot instances (primary node capacity)
- ✅ gp3 EBS volumes everywhere
- ✅ Single NAT in dev, per-AZ in prod
- ✅ VPC endpoints — eliminate NAT charges for ECR/S3/STS traffic
- ✅ ECR lifecycle — keep last 10, expire untagged after 7 days
- ✅ Cluster Autoscaler — scales to zero when idle
- ✅ AMP + AMG — no EC2 for Prometheus/Grafana
- ✅ Node Termination Handler — graceful Spot drain (avoids stuck pods)

---

## ⚠️ Hard Rules for Claude Code

1. **Keep it simple** — junior-readable in 60 seconds or simplify it
2. **Never hardcode** account IDs, regions, CIDRs, or ARNs
3. **Never skip `outputs.tf`** — every module exports key attributes
4. **Never use `count` for multi-AZ resources** — use `for_each`
5. **Always use `locals.tf`** for computed names
6. **Always validate** with `terraform fmt` + `terraform validate`
7. **Always use data sources** for existing AWS resources
8. **Never store secrets in `.tfvars`** — use SSM / Secrets Manager
9. **Always add lifecycle rules** to node groups and ECR repos
10. **Helm provider** configured with EKS `endpoint` + `cluster_ca_certificate`
11. **AMP + Grafana OSS in-cluster** — AMG is optional (not available in ap-south-1)
12. **Grafana datasource = in-cluster Prometheus** — do NOT use SigV4 to AMP directly (broken in Grafana 11)
13. **Comment every resource block** — purpose + why
14. **Explicit `depends_on`** in environment `main.tf` — for safe destroy
15. **Every `.tfvars` variable has a comment** — no exceptions
16. **EKS endpoint always parameterised** — never hardcode `true`/`false`
17. **KMS key rotation always `true`** — never disable
18. **Audit logs always enabled** — `api`, `audit`, `authenticator`
19. **VPC endpoints always created** — S3, ECR, STS, EC2
20. **Node Termination Handler always deployed** — required for Spot
21. **ALB controller: `wait = true`** — all other helm charts must `depends_on` it
22. **Cluster autoscaler SA name: pin to `cluster-autoscaler`** via `rbac.serviceAccount.name`
23. **Use `t3.large` nodes** for full stack — t3.medium has 17 pod limit, not enough for ArgoCD + monitoring + system pods
24. **Monitoring namespace needs allow-all-egress NetworkPolicy** — default-deny blocks Prometheus scraping
25. **Grafana persistence: `enabled = false`** in dev — EBS AZ affinity causes scheduling failures on 2-node clusters

---

## 🛠️ Common Claude Code Tasks

```bash
# Full scaffold in dependency order
"Create the entire infra/ structure from CLAUDE.md, module by module in order"

# Specific modules
"Create the kms module with key rotation enabled and a comment explaining why"
"Create the vpc module including VPC endpoints for S3, ECR, STS, and EC2"
"Create the cluster_defaults module with PDB, LimitRange, and default-deny NetworkPolicy"
"Create the monitoring module with AMP, Prometheus agent, AMG, both data sources,
 alert rules for CPU/memory/OOMKill, and document the Grafana dashboard IDs to import"

# GitHub setup
"Create the GitHub Actions workflows for terraform plan on PR and apply on main merge"
"Create the .pre-commit-config.yaml with terraform fmt, validate, and tflint hooks"

# Wire everything
"Update environments/dev/main.tf with all module calls and explicit depends_on"

# Validate
"Run terraform fmt and validate across all modules and fix issues"

# Audit
"Review all IAM policies for least privilege"
"Review all modules against the Hard Rules in CLAUDE.md and report any violations"
```

---

## 📎 Reference Links

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [IRSA](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [VPC Endpoints for EKS](https://docs.aws.amazon.com/eks/latest/userguide/private-cluster.html)
- [AMP](https://docs.aws.amazon.com/prometheus/latest/userguide/)
- [AMG](https://docs.aws.amazon.com/grafana/latest/userguide/)
- [Prometheus Agent Mode](https://prometheus.io/docs/prometheus/latest/feature_flags/#prometheus-agent)
- [FluentBit on EKS](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-setup-logs-FluentBit.html)
- [CloudWatch Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html)
- [Node Termination Handler](https://github.com/aws/aws-node-termination-handler)
- [Cluster Autoscaler](https://docs.aws.amazon.com/eks/latest/userguide/autoscaling.html)
- [ArgoCD](https://argo-cd.readthedocs.io/en/stable/)
- [GitHub Actions + OIDC AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
