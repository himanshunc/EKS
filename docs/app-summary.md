# App Deployment — How It All Works

---

## What We Built

A simple Node.js app running inside the EKS cluster, exposed to the internet via an AWS Application Load Balancer.

```
Internet
    │
    ▼
AWS ALB (internet-facing)
    │
    └── /*  ──►  nodeapp pod (Node.js HTTP server, port 3000)
```

---

## The App

### nodeapp (`apps/nodeapp/`)

A minimal Node.js HTTP server with no dependencies. Two endpoints:

| Endpoint | Purpose |
|---|---|
| `GET /` | Returns JSON: message, version (git SHA), request path |
| `GET /health` | Returns `ok` — used by ALB and Kubernetes readiness probe |

`APP_VERSION` is set by CI to the short git SHA of the commit that built the image.
Open the ALB URL and read the `version` field to confirm which commit is running.

---

## Folder Structure

```
eks-claude/
│
├── apps/
│   └── nodeapp/
│       ├── server.js      ← Node.js source code
│       ├── package.json   ← app metadata (no dependencies)
│       └── Dockerfile     ← how to build the container image
│
├── k8s/
│   └── nodeapp/
│       ├── namespace.yaml    ← creates the "nodeapp" namespace
│       ├── deployment.yaml   ← 2 pods, which image, resource limits, health probes
│       ├── service.yaml      ← internal ClusterIP (ALB → pod via target-type: ip)
│       └── ingress.yaml      ← ALB config (internet-facing, HTTP 80)
│
├── k8s/
│   └── argocd/
│       └── app-nodeapp.yaml  ← ArgoCD Application (applied once to bootstrap)
│
└── .github/
    └── workflows/
        └── ci-nodeapp.yml    ← CI pipeline (build → push → update manifest)
```

---

## How a Deployment Happens — Step by Step

```
Step 1 — You change code
         Edit apps/nodeapp/server.js
         git commit + git push origin main

Step 2 — GitHub Actions triggers (ci-nodeapp.yml)
         Trigger condition: push to main + file changed under apps/nodeapp/**

Step 3 — CI authenticates to AWS (no passwords)
         GitHub mints a short-lived OIDC token for this workflow run
         AWS exchanges it for temporary credentials (expire in 1 hour)
         No AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY stored anywhere

Step 4 — CI builds the Docker image
         docker build apps/nodeapp/
         Tags it as: 500849274222.dkr.ecr.ap-south-1.amazonaws.com/gitops-dev-worker:<sha>

Step 5 — CI pushes the image to ECR
         docker push (SHA tag + "latest")

Step 6 — CI updates the manifest
         sed replaces the image line in k8s/nodeapp/deployment.yaml:
         Before: image: ...gitops-dev-worker:old-sha
         After:  image: ...gitops-dev-worker:new-sha

Step 7 — CI commits and pushes the manifest change
         git commit -m "ci: deploy nodeapp <sha> [skip ci]"
         git pull --rebase origin main   ← handles parallel CI runs
         git push origin main

Step 8 — ArgoCD detects the new commit (within 3 minutes, or force refresh)
         kubectl patch app nodeapp -n argocd -p '{"operation":{"sync":{"revision":"HEAD"}}}' --type merge

Step 9 — Kubernetes rolls out the new version (zero downtime)
         New pod starts with the new image
         Readiness probe (/health) must pass before traffic shifts
         Old pod is terminated only after new one is Ready

Step 10 — Confirm
          Open the ALB URL in browser
          "version" field shows the new git SHA
```

---

## How ArgoCD Manages the App

One ArgoCD Application object (applied once with kubectl):

```
k8s/argocd/app-nodeapp.yaml
  │
  └── watches: k8s/nodeapp/  in GitHub repo himanshunc/EKS
        │
        └── deploys to: nodeapp namespace in the cluster
```

**Key behaviours:**
- `automated.prune: true` — resources removed from Git are deleted from the cluster
- `automated.selfHeal: true` — manual `kubectl edit` changes are reverted by ArgoCD
- `CreateNamespace=true` — ArgoCD creates the `nodeapp` namespace if it doesn't exist

---

## What Happens If ArgoCD Is Destroyed

ArgoCD is stateless. The nodeapp pods keep running — Kubernetes does not delete them.

**Restore ArgoCD:**
```powershell
cd C:\Projects\eks-claude\Infra\environments\dev
terraform apply -target=module.argocd -auto-approve
kubectl apply -f k8s/argocd/app-nodeapp.yaml
```

ArgoCD re-reads the manifest from Git and syncs. Everything is back.

**Restore entire cluster from scratch:**
```powershell
terraform apply -auto-approve
kubectl apply -f k8s/argocd/app-nodeapp.yaml
# ArgoCD syncs → app is running again
# ECR image still exists — no need to re-run CI
```

---

## How to Roll Back

```powershell
# Find the last good commit SHA in the manifest
git log k8s/nodeapp/deployment.yaml

# Revert the manifest to the previous image tag
git revert HEAD
git push origin main
# ArgoCD detects the revert → rolls back automatically
```

---

## Useful Commands

```powershell
# Check pods are running
kubectl get pods -n nodeapp

# See which image is deployed
kubectl get deployment nodeapp -n nodeapp -o jsonpath="{.spec.template.spec.containers[0].image}"

# Watch a rollout in real time
kubectl rollout status deployment/nodeapp -n nodeapp

# Get the ALB URL
kubectl get ingress -n nodeapp

# Check ArgoCD app status
kubectl get applications -n argocd

# Stream pod logs
kubectl logs -n nodeapp -l app=nodeapp -f

# Describe a pod (when it won't start)
kubectl describe pod -n nodeapp -l app=nodeapp
```
