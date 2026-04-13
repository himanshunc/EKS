# App Deployment — How It All Works

---

## What We Built

Two sample apps running inside the EKS cluster, exposed to the internet via a single AWS Load Balancer.

```
Internet
    │
    ▼
AWS ALB (one load balancer, two apps)
    │
    ├── /api/*   ──►  API pod       (Go HTTP server, port 8080)
    └── /*       ──►  Frontend pod  (nginx serving HTML, port 80)
```

The frontend page calls `/api/` in the browser. The ALB routes that call to the API pod.
You see the API version badge update every time CI deploys a new version.

---

## The Two Apps

### API (`apps/api/`)

A minimal Go HTTP server. Two endpoints:

| Endpoint | Purpose |
|---|---|
| `GET /` | Returns JSON: message, version (git SHA), timestamp, status |
| `GET /health` | Returns `ok` — used by ALB and Kubernetes to check the pod is alive |

The `APP_VERSION` environment variable is set by CI to the git SHA of the commit that built the image.
This is how you can see exactly which commit is running — open `/api/` and read the `version` field.

### Frontend (`apps/frontend/`)

A static HTML page served by nginx. It:
1. Fetches `/api/` using JavaScript
2. Displays the API response and version badge on the page
3. Shows both services as "Running" when healthy

nginx also exposes `/health` for the ALB health check.

---

## Folder Structure

```
eks-claude/
│
├── apps/
│   ├── api/
│   │   ├── main.go       ← Go source code
│   │   ├── go.mod        ← Go module definition
│   │   └── Dockerfile    ← how to build the container image
│   │
│   └── frontend/
│       ├── index.html    ← the web page
│       ├── nginx.conf    ← nginx config (routes + /health)
│       └── Dockerfile    ← how to build the container image
│
├── k8s/
│   └── apps/
│       ├── namespace.yaml         ← creates the "apps" namespace
│       ├── ingress.yaml           ← ALB config (path routing rules)
│       ├── api/
│       │   ├── deployment.yaml    ← how many pods, which image, resource limits
│       │   ├── service.yaml       ← internal DNS name for the api pods
│       │   └── networkpolicy.yaml ← firewall rules for the api pods
│       └── frontend/
│           ├── deployment.yaml
│           ├── service.yaml
│           └── networkpolicy.yaml
│
└── .github/
    └── workflows/
        ├── ci-api.yml        ← CI pipeline for the API
        └── ci-frontend.yml   ← CI pipeline for the frontend
```

---

## How a Deployment Happens — Step by Step

### Normal flow (every code change)

```
Step 1 — You change code
         Edit apps/api/main.go (e.g. change the message)
         git commit + git push origin main

Step 2 — GitHub Actions triggers (ci-api.yml)
         Trigger condition: push to main + file changed under apps/api/**
         The workflow runs on a GitHub-hosted Ubuntu runner

Step 3 — CI authenticates to AWS (no passwords)
         GitHub mints a short-lived OIDC token for this specific workflow run
         AWS sees the token, checks it came from repo himanshunc/EKS
         AWS hands back temporary credentials (expire in 1 hour)
         No AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY stored anywhere

Step 4 — CI builds the Docker image
         docker build apps/api/
         Tags it as: 500849274222.dkr.ecr.ap-south-1.amazonaws.com/gitops-dev-api:a1b2c3d
         The tag is the short git SHA — unique per commit, traceable back to the code

Step 5 — CI pushes the image to ECR
         docker push (both the SHA tag and "latest")
         Image is now stored in AWS, accessible to your cluster nodes

Step 6 — CI updates the manifest
         sed replaces the image line in k8s/apps/api/deployment.yaml:
         Before: image: ...gitops-dev-api:old-sha
         After:  image: ...gitops-dev-api:a1b2c3d

Step 7 — CI commits and pushes the manifest change
         git commit -m "ci: update api image to a1b2c3d"
         git push origin main
         This commit does NOT re-trigger CI (it only touches k8s/, not apps/)

Step 8 — ArgoCD detects the new commit (within 3 minutes)
         ArgoCD polls GitHub every 3 minutes
         It sees deployment.yaml has a new image tag
         It runs kubectl apply on the updated manifest

Step 9 — Kubernetes rolls out the new version
         Starts 1 new pod with the new image
         Waits for /health to return 200 (readiness probe)
         Only then removes the old pod
         Result: zero downtime — traffic never drops

Step 10 — Done
          Open the browser → reload the page
          The version badge now shows the new git SHA
          You can verify which exact commit is running
```

---

## How ArgoCD Manages the Apps

ArgoCD watches three Application objects (applied once with kubectl):

| ArgoCD App | Watches this path | Deploys to |
|---|---|---|
| `apps-ingress` | `k8s/apps/namespace.yaml` + `k8s/apps/ingress.yaml` | `apps` namespace |
| `api` | `k8s/apps/api/` | `apps` namespace |
| `frontend` | `k8s/apps/frontend/` | `apps` namespace |

**Key behaviours:**

- `automated.prune: true` — if you delete a file from Git, ArgoCD deletes the resource from the cluster
- `automated.selfHeal: true` — if someone manually runs `kubectl edit` to change something, ArgoCD reverts it within minutes
- ArgoCD is the only thing that should change the cluster. Git is the source of truth.

---

## What Happens If ArgoCD Is Destroyed

ArgoCD itself is stateless. The Application definitions live in Git (`k8s/argocd/`). The actual app manifests (Deployments, Services, etc.) still exist in the cluster — they are not deleted when ArgoCD goes down.

### Scenario 1: ArgoCD pod crashes / restarts
Nothing bad happens. The pods keep running. ArgoCD restarts and re-syncs automatically.

### Scenario 2: ArgoCD Helm release is deleted
The ArgoCD pods stop. Your apps (api, frontend) keep running — Kubernetes does not delete them.
No new deployments happen until ArgoCD is restored.

**To restore:**
```powershell
# Re-run Terraform — it will reinstall ArgoCD via Helm
cd C:\Projects\eks-claude\Infra\environments\dev
terraform apply -target=module.argocd -auto-approve

# Re-apply the Application manifests
kubectl apply -f k8s/argocd/app-ingress.yaml
kubectl apply -f k8s/argocd/app-api.yaml
kubectl apply -f k8s/argocd/app-frontend.yaml
```

ArgoCD re-reads the manifests from Git and syncs. Everything is back.

### Scenario 3: Entire cluster is destroyed and rebuilt
Apps are gone with the cluster. But Git has everything needed to recreate them.

**To restore:**
```powershell
# 1. Re-apply full infra
cd C:\Projects\eks-claude\Infra\environments\dev
terraform apply -auto-approve

# 2. Bootstrap ArgoCD apps
kubectl apply -f k8s/argocd/app-ingress.yaml
kubectl apply -f k8s/argocd/app-api.yaml
kubectl apply -f k8s/argocd/app-frontend.yaml

# 3. ArgoCD syncs — apps are running again
```

The ECR images still exist (lifecycle policy keeps last 10). The last deployed versions are
restored immediately without re-running CI.

---

## How to Roll Back a Bad Deployment

### Option A: Git revert (recommended)
```powershell
# Find the last good commit
git log k8s/apps/api/deployment.yaml

# Revert the manifest to the previous image tag
git revert HEAD
git push origin main
# ArgoCD detects the revert → rolls back automatically
```

### Option B: Manually edit the manifest
```powershell
# Edit k8s/apps/api/deployment.yaml
# Change the image tag back to the previous SHA
git commit -am "revert: roll back api to previous version"
git push origin main
```

### Option C: kubectl rollout (bypasses GitOps — ArgoCD will re-sync and undo this)
```powershell
kubectl rollout undo deployment/api -n apps
# WARNING: ArgoCD will revert this back to whatever is in Git within minutes
# Use Option A or B if you want the rollback to stick
```

---

## Useful Commands

```powershell
# Check all apps are running
kubectl get pods -n apps

# See which image is currently deployed
kubectl get deployment api -n apps -o jsonpath="{.spec.template.spec.containers[0].image}"

# Watch a rollout in real time
kubectl rollout status deployment/api -n apps

# Get the ALB URL (open in browser)
kubectl get ingress -n apps

# Check ArgoCD app status
kubectl get applications -n argocd

# Stream API pod logs
kubectl logs -n apps -l app=api -f

# Stream frontend pod logs
kubectl logs -n apps -l app=frontend -f

# Describe a pod (useful when it won't start)
kubectl describe pod -n apps -l app=api
```

---

## Security Notes

| What | How it is protected |
|---|---|
| Docker images | Stored in private ECR — only your cluster nodes can pull them |
| AWS credentials in CI | OIDC — no stored secrets, credentials expire in 1 hour |
| Pod-to-pod traffic | Default-deny NetworkPolicy — api and frontend can't talk to each other unless explicitly allowed |
| External traffic | Only port 80 via the ALB — pods are not directly reachable from the internet |
| Resource limits | LimitRange prevents any pod from consuming all node CPU/memory |
