# Application Delivery Flow — Interview Reference

## The Big Picture

This project delivers a Node.js application to AWS EKS using a fully automated
GitOps pipeline. The Git repository is the single source of truth — every change
to infrastructure or application goes through Git, and automated systems reconcile
the live state to match.

---

## Architecture Overview

```
Developer
   │
   │  git push
   ▼
GitHub Repository
   │
   ├──► GitHub Actions (CI)
   │         │ lint → test → docker build → trivy scan → push to ECR
   │         │ update image tag in helm/myapp/values.yaml → git commit
   │
   └──► ArgoCD (CD) watches repo
             │ detects values.yaml change
             │ renders Helm chart
             ▼
         EKS Cluster (AWS)
             │
             ├── Deployment (pods running the app)
             ├── Service (internal load balancing)
             └── Ingress → ALB (public URL)
```

---

## Components and Why Each Exists

### AWS EKS (Elastic Kubernetes Service)
- Managed Kubernetes control plane — AWS handles API server, etcd, upgrades
- Worker nodes are EC2 instances (t3.large) in a managed node group
- Cluster autoscaler adds/removes nodes based on pod demand
- Why EKS over self-managed: no control plane ops, native AWS IAM integration

### Terraform (Infrastructure as Code)
- Creates everything: VPC, subnets, EKS cluster, IAM roles, ECR, ALB controller
- State stored in S3 with DynamoDB locking — safe for team use
- Module structure: kms → vpc → security_groups → iam → eks → irsa → node_groups → helm_addons → argocd
- Why Terraform: reproducible, version-controlled, plan before apply

### Helm (Kubernetes Package Manager)
- Packages all Kubernetes manifests (Deployment, Service, Ingress, HPA) into one chart
- `values.yaml` externalises every configurable value — same chart works across environments
- `values-dev.yaml` overrides defaults for dev (1 replica, no HPA)
- Templates use `{{ .Values.image.tag }}` — CI updates only this one field
- Why Helm over raw manifests: reusable, parameterised, easy rollback with `helm rollback`

### ArgoCD (GitOps Continuous Delivery)
- Runs inside the cluster, watches the Git repo continuously
- When it detects a change in `helm/myapp/`, it renders the chart and applies it
- `selfHeal: true` — if someone manually changes a resource, ArgoCD reverts it
- `prune: true` — resources removed from the chart are deleted from the cluster
- Why ArgoCD: Git is the source of truth, every deployment is auditable, no kubectl in CI

### GitHub Actions (CI)
- Triggered on push to `apps/myapp/**`
- Steps: ESLint → unit tests → Docker build → Trivy CVE scan → ECR push → update Helm values
- Uses OIDC to authenticate to AWS — no static access keys stored anywhere
- Why OIDC: short-lived credentials per workflow run, no secret rotation needed

### AWS ALB (Application Load Balancer)
- Provisioned automatically by the AWS Load Balancer Controller from the Ingress resource
- Routes external HTTP traffic to pods
- Why ALB over NodePort: managed, supports path/host routing, integrates with ACM for TLS

### IRSA (IAM Roles for Service Accounts)
- Binds a Kubernetes service account to an IAM role using the cluster's OIDC provider
- Each component gets least-privilege permissions: ALB controller, cluster autoscaler, EBS CSI
- Why IRSA: no EC2 instance profile sharing, pod-level permissions, no static credentials in pods

---

## The GitOps Flow — Step by Step

```
1. Developer edits apps/myapp/server.js
2. git push → triggers ci-myapp.yml workflow
3. CI: npm run lint           → catches syntax/style issues
4. CI: npm test               → runs unit tests (node:test, no HTTP server)
5. CI: docker build           → builds image locally for scanning
6. CI: trivy scan             → fails build if CRITICAL CVEs with fixes exist
7. CI: docker push ECR        → pushes :SHA tag and :latest tag
8. CI: sed image.tag          → updates helm/myapp/values.yaml with new SHA
9. CI: git commit + push      → commits "[skip ci]" so it doesn't retrigger
10. ArgoCD polls repo (3 min) → detects values.yaml changed
11. ArgoCD: helm template      → renders chart with new image tag
12. ArgoCD: kubectl apply      → rolling update — new pods up before old ones down
13. User hits ALB URL          → sees updated response
```

---

## Helm Chart Structure Explained

```
helm/myapp/
├── Chart.yaml          # chart name, version, appVersion
├── values.yaml         # all defaults — CI updates image.tag here
├── values-dev.yaml     # dev overrides (1 replica, HPA disabled)
└── templates/
    ├── _helpers.tpl    # reusable named templates (myapp.fullname, myapp.labels)
    ├── deployment.yaml # uses {{ .Values.image.tag }}, {{ .Values.replicaCount }}
    ├── service.yaml    # ClusterIP — ALB controller talks to pods directly
    ├── ingress.yaml    # ALB annotations, conditional on {{ .Values.ingress.enabled }}
    └── hpa.yaml        # conditional on {{ .Values.hpa.enabled }}
```

**Key concept:** `_helpers.tpl` defines reusable blocks like `myapp.labels` and
`myapp.selectorLabels`. Every template calls these instead of repeating label logic.
Selector labels are kept separate from common labels because selectors are immutable
after a Deployment is created.

---

## Environment Promotion Pattern

```
values.yaml          ← base (used in all environments)
values-dev.yaml      ← dev overrides merged on top
values-staging.yaml  ← staging overrides (future)
values-prod.yaml     ← prod overrides (future)
```

ArgoCD Application specifies which files to merge:
```yaml
helm:
  valueFiles:
    - values.yaml
    - values-dev.yaml
```

To promote to prod: create `values-prod.yaml` and a new ArgoCD Application
pointing to the same chart with `values-prod.yaml` as the override.

---

## Security Highlights

| Area | Approach |
|------|----------|
| No static AWS keys in CI | OIDC — GitHub gets a short-lived token per run |
| No static keys in pods | IRSA — pods assume IAM roles via service account annotation |
| Image CVE scanning | Trivy blocks push if CRITICAL fixable CVEs found |
| EKS secrets encrypted | KMS key encrypts etcd secrets at rest |
| Network isolation | Default-deny NetworkPolicy on all namespaces |
| State file security | S3 encryption + DynamoDB locking |

---

## Rollback Strategy

**Application rollback** (ArgoCD):
```bash
argocd app history myapp        # list all deployments
argocd app rollback myapp <ID>  # roll back to a specific revision
```

**Infrastructure rollback** (Terraform):
- S3 state versioning allows restoring a previous state
- Re-run apply with the previous commit — Terraform calculates the diff

---

## Key Interview Points

1. **"Why GitOps?"** — Auditability (every change is a Git commit), consistency
   (cluster always matches the repo), easy rollback (revert the commit)

2. **"Why Helm over raw manifests?"** — Parameterisation (same chart, different values
   per environment), rollback built-in, widely understood standard

3. **"How do you avoid drift?"** — ArgoCD `selfHeal: true` reverts any out-of-band
   changes. The cluster always converges to what's in Git.

4. **"How does the image tag get updated?"** — CI writes the git SHA into
   `helm/myapp/values.yaml` and commits it. ArgoCD detects the commit and redeploys.
   The SHA is the tag — every deployment is traceable to a specific commit.

5. **"How do you handle secrets?"** — Currently environment variables from values.yaml.
   Next step: AWS Secrets Manager + External Secrets Operator to inject secrets as
   Kubernetes secrets without storing them in Git.
