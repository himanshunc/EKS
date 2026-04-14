# Implementation Guide — EKS GitOps Platform

Complete step-by-step guide to everything built in this project.

---

## Prerequisites

- AWS account with admin IAM user (`terraform-admin`)
- AWS CLI configured locally
- Terraform >= 1.6.0
- kubectl
- Helm 3
- GitHub repo with Actions enabled
- GitHub repo secrets: `TF_ROLE_ARN`, `AWS_ROLE_ARN`
- GitHub repo variables: `AWS_REGION`, `AWS_ACCOUNT_ID`

---

## Step 0 — Bootstrap (Run Once)

Creates the S3 bucket and DynamoDB table for Terraform remote state.
Must be done before any other Terraform.

```bash
cd Infra/bootstrap
terraform init
terraform apply
# Note the outputs: bucket name, table name
```

Copy outputs into `Infra/environments/dev/backend.tf`.

---

## Step 1 — Pre-existing AWS Resources

These must exist in AWS before Terraform CI can run.
Create them once manually (or via a separate bootstrap script).

### GitHub Actions OIDC Provider
Allows GitHub Actions to authenticate to AWS without static keys.

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### GitHub Actions IAM Role
Allows the CI/CD workflows to assume AWS permissions via OIDC.

- Create role `github-action-role` in IAM
- Trust policy: allow `token.actions.githubusercontent.com` to assume it
- Attach `AdministratorAccess` (scope down in prod)
- Copy the ARN → set as `TF_ROLE_ARN` GitHub secret

---

## Step 2 — Terraform Infrastructure

All infrastructure is in `Infra/environments/dev/`.

### Module Dependency Order

```
kms → vpc → security_groups → iam → eks → irsa → node_groups
→ ecr → cluster_defaults → helm_addons → argocd → monitoring → logging
```

### What Each Module Creates

| Module | Resources |
|--------|-----------|
| `kms` | KMS key for EKS secrets encryption |
| `vpc` | VPC, public/private subnets, NAT gateway, route tables |
| `security_groups` | Cluster SG, node SG with least-privilege rules |
| `iam` | EKS cluster role, node role, GitHub Actions OIDC roles |
| `eks` | EKS cluster, OIDC provider, vpc-cni, kube-proxy addons |
| `irsa` | IRSA roles: ALB controller, cluster autoscaler, EBS CSI, AMP, Grafana |
| `node_groups` | Managed node group (t3.large, Spot + On-demand mix) |
| `ecr` | ECR repositories with lifecycle policies and scan-on-push |
| `cluster_defaults` | Namespaces, LimitRanges, default-deny NetworkPolicies |
| `helm_addons` | ALB controller, metrics-server, cluster autoscaler, EBS CSI, NTH |
| `argocd` | ArgoCD via Helm, ALB ingress, NetworkPolicy, PodDisruptionBudget |
| `monitoring` | AMP workspace, in-cluster Prometheus + Grafana via Helm |
| `logging` | FluentBit, CloudWatch log groups |

### Apply via CI

```
push to main (Infra/**) → terraform plan → manual approval → terraform apply
```

The apply workflow:
1. Saves plan to binary file (`terraform plan -out=tfplan.binary`)
2. Uploads as GitHub artifact
3. Pauses at `environment: production` gate — reviewer approves
4. Downloads artifact and applies the exact saved plan (`terraform apply tfplan.binary`)

### Apply Locally (First Time / Recovery)

```bash
cd Infra/environments/dev
terraform init
terraform plan
terraform apply
```

---

## Step 3 — Cluster Access

After apply, configure kubectl:

```bash
aws eks update-kubeconfig --name gitops-dev-eks-cluster --region ap-south-1
```

Grant your IAM user cluster access (EKS Access Entry API):

```powershell
aws eks create-access-entry `
  --cluster-name gitops-dev-eks-cluster `
  --principal-arn arn:aws:iam::500849274222:user/terraform-admin `
  --region ap-south-1

aws eks associate-access-policy `
  --cluster-name gitops-dev-eks-cluster `
  --principal-arn arn:aws:iam::500849274222:user/terraform-admin `
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy `
  --access-scope type=cluster `
  --region ap-south-1
```

---

## Step 4 — Verify Cluster Health

```bash
kubectl get nodes                  # all nodes Ready
kubectl get pods -A                # no CrashLoopBackOff or Pending
kubectl get storageclass           # gp3 is default
kubectl top nodes                  # metrics-server working
```

---

## Step 5 — ArgoCD Setup

ArgoCD is deployed by Terraform (helm_addons module). Get the UI URL:

```bash
kubectl get ingress -n argocd
```

Get initial password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode && echo
```

Login: `admin` / `<password above>`
Change password immediately after first login.

---

## Step 6 — Application Deployment (nodeapp — Raw Manifests)

`nodeapp` uses raw Kubernetes manifests — the traditional approach.

**Manifests location:** `k8s/nodeapp/`
- `namespace.yaml` — creates the `nodeapp` namespace
- `deployment.yaml` — image tag updated by CI on every build
- `service.yaml` — ClusterIP service
- `ingress.yaml` — ALB ingress

**ArgoCD Application:**
```bash
kubectl apply -f k8s/argocd/app-nodeapp.yaml
```

**CI Flow (`.github/workflows/ci-nodeapp.yml`):**
1. ESLint + unit tests
2. Docker build → Trivy scan → ECR push
3. `sed` updates `image:` line in `k8s/nodeapp/deployment.yaml`
4. CI commits and pushes the manifest change
5. ArgoCD detects the commit → applies the updated deployment

---

## Step 7 — Application Deployment (myapp — Helm Chart)

`myapp` uses a Helm chart — the recommended approach for production.

**Helm chart location:** `helm/myapp/`

```
helm/myapp/
├── Chart.yaml           # chart metadata
├── values.yaml          # defaults, CI updates image.tag here
├── values-dev.yaml      # dev overrides (1 replica, no HPA)
└── templates/
    ├── _helpers.tpl     # reusable named templates
    ├── deployment.yaml  # parameterised with {{ .Values.* }}
    ├── service.yaml
    ├── ingress.yaml     # conditional: only rendered if ingress.enabled=true
    └── hpa.yaml         # conditional: only rendered if hpa.enabled=true
```

**ArgoCD Application:**
```bash
kubectl apply -f k8s/argocd/app-myapp.yaml
```

ArgoCD merges `values.yaml` + `values-dev.yaml` and renders the chart.

**CI Flow (`.github/workflows/ci-myapp.yml`):**
1. ESLint + unit tests
2. Docker build → Trivy scan → ECR push (`gitops-dev-api`)
3. `sed` updates only `image.tag` in `helm/myapp/values.yaml`
4. CI commits and pushes
5. ArgoCD detects the values change → re-renders chart → rolling update

---

## Step 8 — GitOps Flow Comparison

| | nodeapp | myapp |
|---|---|---|
| Manifests | Raw YAML | Helm chart |
| CI updates | `deployment.yaml` image line | `values.yaml` image.tag |
| Environment config | Separate manifest files | `values-dev.yaml` override |
| Rollback | `git revert` the manifest | `argocd app rollback` or `git revert` |
| Reusability | One environment only | Same chart, different values files |

---

## Step 9 — CI/CD Workflows Summary

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `terraform-plan.yml` | PR to main (Infra/**) | fmt + validate + plan, posts to PR comment |
| `terraform-apply.yml` | Push to main (Infra/**) | plan → save artifact → approve → apply exact plan |
| `ci-nodeapp.yml` | Push to main (apps/nodeapp/**) | lint → test → build → scan → push → update manifest |
| `ci-myapp.yml` | Push to main (apps/myapp/**) | lint → test → build → scan → push → update helm values |

---

## Step 10 — Key Design Decisions

### Why separate `iam` and `irsa` modules?
`iam` creates the EKS cluster role and node role — needed *before* the cluster exists.
`irsa` creates roles that use the OIDC provider URL — only available *after* the cluster
is created. Splitting them avoids a circular dependency.

### Why is the EKS OIDC provider a `resource` but the GitHub Actions OIDC provider a `data` source?
- EKS OIDC: cluster-specific URL, created fresh with each cluster → `resource`
- GitHub Actions OIDC: account-level, created once, exists before Terraform runs → `data`

### Why `terraform apply tfplan.binary` instead of `terraform apply -auto-approve`?
Saves the plan at review time and applies the exact same plan after approval.
Without this, there is a re-plan between approval and apply — if anything changed
in AWS during that window, the apply could do something different from what was reviewed.

### Why t3.large instead of t3.medium?
t3.medium hits the 17-pod limit per node when running the full stack (ArgoCD +
monitoring + logging + system pods). t3.large supports 35 pods per node.

### Why `--insecure` on ArgoCD server?
The ALB terminates TLS. ArgoCD serves plain HTTP internally to the ALB.
This avoids managing a certificate inside the cluster for dev.

---

## Destroy

```powershell
.\scripts\destroy.ps1
```

Before destroying, remove ArgoCD applications to avoid finalizer deadlocks:

```bash
kubectl delete application myapp -n argocd
kubectl delete application nodeapp -n argocd
```

---

## Costs (Approximate, ap-south-1)

| Resource | Monthly Cost |
|----------|-------------|
| EKS control plane | ~$72 |
| 2x t3.large nodes (Spot) | ~$25-40 |
| NAT Gateway (single) | ~$32 |
| ALB (per ingress) | ~$16 each |
| S3 + DynamoDB (state) | < $1 |
| ECR storage | < $1 |
| **Total (approx)** | **~$150-170** |

Destroy when not in use to avoid charges.
