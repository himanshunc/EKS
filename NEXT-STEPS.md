# EKS Deployment - Next Steps

## Where are you now?

```
[x] Step 0 - Bootstrap     (S3 bucket + DynamoDB created, backend.tf patched)
[ ] Step 1 - Init
[ ] Step 2 - Plan
[ ] Step 3 - Apply
[ ] Step 4 - Verify
[ ] Step 5 - CI/CD Setup   (GitHub secrets + ArgoCD bootstrap)
[ ] Step 6 - Test the pipeline
```

---

## Step 1 - Init

Initialises the dev environment with the S3 remote backend.

```powershell
.\scripts\init.ps1
```

What it does:
- Copies backend.tf and versions.tf into infra/environments/dev/
- Runs terraform init (downloads all providers: aws, kubernetes, helm, grafana, tls)

Expected output: "Terraform has been successfully initialized!"

---

## Step 2 - Plan

Reviews everything Terraform will create before touching AWS.

```powershell
.\scripts\plan.ps1
```

What to check in the plan output:
- Should show ~80-100 resources to add, 0 to destroy
- Confirm cluster name shows as: myeks-dev-eks-cluster
- Confirm region shows as: ap-south-1
- No unexpected destroys or replacements

---

## Step 3 - Apply

Deploys the full stack. Takes 15-20 minutes.

```powershell
.\scripts\apply.ps1
```

What happens:
- Phase 1 (~3 min)  : KMS key, VPC, subnets, NAT, security groups
- Phase 2 (~15 min) : EKS cluster, nodes, IAM, ECR, ArgoCD, Prometheus, Grafana, FluentBit

Go get a coffee. Watch for any errors.

---

## Step 4 - Verify

### See all outputs (cluster name, Grafana URL, ECR URLs)
```powershell
.\scripts\outputs.ps1
```

### Configure kubectl
```powershell
.\scripts\kubeconfig.ps1
```

### Check nodes are Ready
```powershell
kubectl get nodes
```
Expected: 2 nodes, STATUS = Ready

### Check all system pods are running
```powershell
kubectl get pods -A
```
Expected: all pods Running or Completed, none in CrashLoopBackOff

---

## Step 5 - Access Grafana

1. Run `.\scripts\outputs.ps1` - copy the `grafana_url` value
2. Open it in your browser
3. Log in via AWS SSO
4. Go to Dashboards -> Import
5. Import dashboard ID `315` (Kubernetes Cluster Overview)
6. Select the AMP data source -> Import

Full dashboard list: docs/grafana-dashboards.md

---

## Useful Day-2 Commands

```powershell
# Watch pods across all namespaces
kubectl get pods -A -w

# Check ArgoCD is running
kubectl get pods -n argocd

# Check monitoring stack
kubectl get pods -n monitoring

# Check logging stack
kubectl get pods -n logging

# View cluster autoscaler logs
kubectl logs -n kube-system -l app.kubernetes.io/name=cluster-autoscaler -f

# View ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller -f
```

---

## Teardown (when done)

```powershell
.\scripts\destroy.ps1
```

Destroys everything in reverse order. Takes ~15 minutes.
To also destroy bootstrap (S3 + DynamoDB) after that:
1. Remove `prevent_destroy = true` from infra/bootstrap/main.tf
2. `cd infra\bootstrap` then `terraform destroy`

---

---

## Step 5 - CI/CD Setup (after terraform apply)

### 5a — Update ArgoCD Application manifests with your repo URL

Edit these two files and replace `YOUR_ORG/YOUR_REPO` with your actual GitHub repo:

```
k8s/argocd/app-api.yaml
k8s/argocd/app-frontend.yaml
k8s/argocd/app-ingress.yaml
```

Also update `terraform.tfvars`:
```hcl
github_org  = "your-actual-github-org"
github_repo = "eks-claude"             # or whatever you named it
```

Then re-run apply to create the GitHub Actions IAM role:
```powershell
.\scripts\apply.ps1
```

### 5b — Get the GitHub Actions role ARN

```powershell
.\scripts\outputs.ps1
# Copy the value of: github_actions_role_arn
```

### 5c — Add GitHub repo secrets and variables

In your GitHub repo → Settings → Secrets and variables → Actions:

**Secrets** (encrypted):
| Name | Value |
|---|---|
| `AWS_ROLE_ARN` | ARN from step 5b (e.g. `arn:aws:iam::500849274222:role/gitops-dev-github-actions`) |

**Variables** (plain text):
| Name | Value |
|---|---|
| `AWS_REGION` | `ap-south-1` |
| `AWS_ACCOUNT_ID` | Your 12-digit AWS account ID |

### 5d — Bootstrap ArgoCD (apply once)

Connect to the cluster, then apply the ArgoCD Application manifests:

```powershell
.\scripts\kubeconfig.ps1

kubectl apply -f k8s/argocd/app-ingress.yaml  -n argocd
kubectl apply -f k8s/argocd/app-api.yaml      -n argocd
kubectl apply -f k8s/argocd/app-frontend.yaml -n argocd
```

Watch ArgoCD sync (takes ~30 seconds):
```powershell
kubectl get applications -n argocd
# STATUS should show: Synced / Healthy
```

### 5e — Get the ALB URL

```powershell
kubectl get ingress -n apps
# Copy the ADDRESS column — this is your ALB DNS name
# Takes ~2 minutes after first apply for ALB to become active
```

Open in browser:
- `http://<ALB-DNS>/`         → Frontend (shows API version badge)
- `http://<ALB-DNS>/api/`     → API JSON response directly

---

## Step 6 — Test the CI/CD pipeline

Make a visible change to trigger the pipeline end-to-end:

```powershell
# 1. Edit the API greeting
#    Open apps/api/main.go and change the "message" string

# 2. Push to main
git add apps/api/main.go
git commit -m "feat: update api greeting"
git push origin main
```

**What happens next (automatically):**
```
1. GitHub Actions detects push to apps/api/
2. Builds Docker image:  gitops-dev-api:<sha>
3. Pushes to ECR
4. Commits k8s/apps/api/deployment.yaml with new image tag
5. ArgoCD detects the new commit (~30s poll)
6. ArgoCD applies the updated Deployment
7. Kubernetes rolls out new pods (zero downtime)
8. Reload the browser — new version badge appears
```

Watch the rollout:
```powershell
kubectl rollout status deployment/api -n apps
kubectl get pods -n apps
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `terraform init` fails with backend error | Check infra/global/backend.tf has correct bucket name |
| EKS nodes not joining | Check node IAM role has AmazonEKSWorkerNodePolicy attached |
| Pods stuck Pending | Run `kubectl describe pod <name>` to see scheduling errors |
| ALB not created | Check ALB controller logs, verify subnet tags are correct |
| Grafana unreachable | Check AMG workspace status in AWS Console |
