# Post-Deployment Reference

Cluster: `gitops-dev-eks-cluster` | Region: `ap-south-1` | Account: `500849274222`

---

## 1. Terraform Outputs

After a successful apply, retrieve all outputs:

```bash
cd Infra/environments/dev
terraform output
```

Key outputs:

| Output | Description |
|--------|-------------|
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | EKS API server URL |
| `cluster_version` | Kubernetes version |
| `vpc_id` | VPC ID |
| `ecr_repository_urls` | ECR repo URLs for CI/CD |
| `grafana_url` | Amazon Managed Grafana URL |
| `amp_endpoint` | AMP remote_write endpoint |
| `log_group_name` | CloudWatch log group |
| `github_actions_role_arn` | IAM role ARN for ECR push (set as `AWS_ROLE_ARN` secret) |
| `github_actions_terraform_role_arn` | IAM role ARN for Terraform CI (set as `TF_ROLE_ARN` secret) |

---

## 2. Cluster Access

### Configure kubeconfig

```bash
aws eks update-kubeconfig --name gitops-dev-eks-cluster --region ap-south-1
```

### Verify your identity

```bash
aws sts get-caller-identity
```

### Grant cluster access to an IAM user/role

If you get `"the server has asked for the client to provide credentials"`, your IAM identity needs an access entry:

```bash
# Step 1 — create the access entry
aws eks create-access-entry \
  --cluster-name gitops-dev-eks-cluster \
  --principal-arn arn:aws:iam::500849274222:user/YOUR_IAM_USER \
  --region ap-south-1

# Step 2 — attach cluster-admin policy
aws eks associate-access-policy \
  --cluster-name gitops-dev-eks-cluster \
  --principal-arn arn:aws:iam::500849274222:user/YOUR_IAM_USER \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster \
  --region ap-south-1
```

Replace `YOUR_IAM_USER` with your IAM username (e.g. `terraform-admin`).

### Access entries already configured by Terraform

| Principal | Access Level |
|-----------|-------------|
| `github-action-role` (via `TF_ROLE_ARN`) | Cluster Admin — Terraform CI |

---

## 3. Verification Steps

### Nodes

```bash
kubectl get nodes -o wide
# Expected: 2-3 t3.large nodes in Ready state
```

### All pods

```bash
kubectl get pods -A
# All pods should be Running or Completed — none in CrashLoopBackOff or Pending
```

### System addons (kube-system)

```bash
kubectl get pods -n kube-system
# Expected pods:
#   aws-load-balancer-controller
#   cluster-autoscaler
#   aws-ebs-csi-driver
#   metrics-server
#   aws-node-termination-handler (on Spot nodes)
#   coredns
#   kube-proxy
#   aws-node (vpc-cni)
```

### Node resource usage

```bash
kubectl top nodes
kubectl top pods -A
```

### Storage class

```bash
kubectl get storageclass
# gp3 should be the default (annotated with storageclass.kubernetes.io/is-default-class=true)
```

### ArgoCD

```bash
kubectl get pods -n argocd
kubectl get svc -n argocd
```

### Monitoring

```bash
kubectl get pods -n monitoring
```

### Application

```bash
kubectl get pods -n apps
kubectl get ingress -A   # shows ALB URLs for all ingresses
```

---

## 4. Service URLs

### ArgoCD UI

Get the ALB URL:

```bash
kubectl get ingress -n argocd
```

Default credentials (change after first login):
- **Username:** `admin`
- **Password:** retrieve with:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d
```

### Grafana (in-cluster)

Get the ALB URL:

```bash
kubectl get ingress -n monitoring
```

Default credentials:
- **Username:** `admin`
- **Password:** `prom-operator` (set in Helm values — change after first login)

### Amazon Managed Grafana (AMG)

```bash
terraform output grafana_url
```

Open the URL in your browser — SSO login via AWS IAM Identity Center.

### Application (nodeapp)

```bash
kubectl get ingress -n apps
# Copy the ADDRESS column — this is the ALB DNS name
```

---

## 5. GitHub Secrets Reference

| Secret | Value | Used by |
|--------|-------|---------|
| `TF_ROLE_ARN` | `arn:aws:iam::500849274222:role/github-action-role` | terraform-plan, terraform-apply |
| `AWS_ROLE_ARN` | from `terraform output github_actions_role_arn` | ci-nodeapp (ECR push) |

Set secrets at: **GitHub repo → Settings → Secrets and variables → Actions**

---

## 6. Useful Commands

```bash
# Check cluster info
kubectl cluster-info

# Watch pod startup in real time
kubectl get pods -A -w

# Describe a failing pod
kubectl describe pod <pod-name> -n <namespace>

# Check ALB controller logs (if ingress not creating)
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check autoscaler logs
kubectl logs -n kube-system -l app=cluster-autoscaler

# List all ingresses and their ALB URLs
kubectl get ingress -A

# Force ArgoCD to sync an app
argocd app sync <app-name>
```
