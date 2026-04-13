# Testing Guide — nodeapp CI/CD Pipeline

---

## 1. Test the Live App

### Get the ALB URL
```powershell
kubectl get ingress -n nodeapp
# Copy the ADDRESS column
```

Current URL: `k8s-nodeapp-nodeapp-0d6baf4878-658314617.ap-south-1.elb.amazonaws.com`

### Hit the endpoints

**Main endpoint — confirms app is running and shows current version:**
```powershell
curl http://<ALB-URL>/
```
Expected response:
```json
{
  "message": "Hello from Node.js - v2!",
  "version": "d80bc5d",
  "path": "/"
}
```
- `message` — the greeting from `server.js`
- `version` — short git SHA of the commit that built the running image
- `path` — the request path

**Health endpoint — used by ALB and Kubernetes probes:**
```powershell
curl http://<ALB-URL>/health
```
Expected response: `ok`

---

## 2. Test the CI/CD Pipeline End-to-End

This is the core test — proves the full GitOps loop works.

### Step 1 — Make a visible change
```powershell
# Edit the message in apps/nodeapp/server.js
# Change: "Hello from Node.js - v2!"
# To:     "Hello from Node.js - v3!"
```

### Step 2 — Push to main
```powershell
git add apps/nodeapp/server.js
git commit -m "feat: update greeting to v3"
git push origin main
```

### Step 3 — Watch GitHub Actions
1. Go to your GitHub repo → Actions tab
2. You should see `CI — nodeapp` workflow triggered within seconds
3. Watch the steps complete:
   - `Checkout` → `Configure AWS credentials` → `Login to ECR`
   - `Build and push Docker image` (~1-2 min)
   - `Update deployment manifest` — commits new image SHA to `k8s/nodeapp/deployment.yaml`

### Step 4 — Watch ArgoCD sync
```powershell
# Poll ArgoCD app status (updates within ~3 minutes)
kubectl get applications -n argocd

# Or force an immediate sync:
kubectl patch app nodeapp -n argocd \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}' \
  --type merge
```
Expected: `STATUS = Synced`, `HEALTH = Healthy`

### Step 5 — Watch the rolling update
```powershell
kubectl rollout status deployment/nodeapp -n nodeapp
# Expected: "deployment "nodeapp" successfully rolled out"

kubectl get pods -n nodeapp
# Expected: new pods Running, old pods Terminated
```

### Step 6 — Confirm in browser
```powershell
curl http://<ALB-URL>/
```
- `message` field should show the updated greeting
- `version` field should show the new git SHA (matches the Actions run)

---

## 3. Verify ArgoCD Is Syncing

```powershell
# Check app status
kubectl get applications -n argocd

# Describe the app for full detail (last sync time, errors)
kubectl describe application nodeapp -n argocd

# Check ArgoCD pods are healthy
kubectl get pods -n argocd
```

**Expected output from `kubectl get applications -n argocd`:**
```
NAME      SYNC STATUS   HEALTH STATUS
nodeapp   Synced        Healthy
```

If status shows `OutOfSync` — ArgoCD has detected a change but hasn't applied it yet. Either wait (~3 min) or force sync:
```powershell
kubectl patch app nodeapp -n argocd \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}' \
  --type merge
```

---

## 4. Test Rollback

```powershell
# 1. Find the previous commit SHA in the manifest history
git log k8s/nodeapp/deployment.yaml

# 2. Revert the last manifest change
git revert HEAD
git push origin main

# 3. ArgoCD detects the revert and rolls back automatically
kubectl rollout status deployment/nodeapp -n nodeapp

# 4. Confirm old version is running
curl http://<ALB-URL>/
# "version" field shows the previous git SHA
```

---

## 5. Useful Test Commands

### Pod health
```powershell
# Are pods running?
kubectl get pods -n nodeapp

# Which image is deployed?
kubectl get deployment nodeapp -n nodeapp \
  -o jsonpath="{.spec.template.spec.containers[0].image}"

# Stream live logs
kubectl logs -n nodeapp -l app=nodeapp -f

# Describe a pod (when it won't start)
kubectl describe pod -n nodeapp -l app=nodeapp
```

### Deployment events
```powershell
# Watch a rollout in real time
kubectl rollout status deployment/nodeapp -n nodeapp

# See rollout history
kubectl rollout history deployment/nodeapp -n nodeapp
```

### ALB and ingress
```powershell
# Get the ALB DNS name
kubectl get ingress -n nodeapp

# Check ingress events (ALB provisioning errors show here)
kubectl describe ingress nodeapp -n nodeapp
```

### CI confirmation
```powershell
# Confirm the image tag in the manifest matches the latest CI run
cat k8s/nodeapp/deployment.yaml | grep image:

# Confirm the same SHA is what ArgoCD deployed
kubectl get deployment nodeapp -n nodeapp \
  -o jsonpath="{.spec.template.spec.containers[0].image}"
```

---

## 6. What Good Looks Like

| Check | Expected |
|---|---|
| `kubectl get pods -n nodeapp` | 2 pods, STATUS = Running |
| `curl http://<ALB-URL>/` | JSON with message + version |
| `curl http://<ALB-URL>/health` | `ok` |
| `kubectl get applications -n argocd` | Synced / Healthy |
| GitHub Actions `ci-nodeapp` | green checkmark |
| `version` in JSON matches last CI commit SHA | yes |

---

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Pods in `ImagePullBackOff` | Wrong image tag or ECR auth | Check `kubectl describe pod` for error; re-run CI |
| `curl` returns 502 | Pod not ready yet | Wait for readiness probe; check `kubectl logs` |
| ArgoCD shows `OutOfSync` for >5 min | ArgoCD sync issue | Force sync with kubectl patch command above |
| CI fails at `Configure AWS credentials` | OIDC trust policy or role ARN wrong | Check GitHub secret `AWS_ROLE_ARN` matches Terraform output |
| CI fails at `git push` | Parallel CI runs race | The workflow uses `git pull --rebase` — re-run the failed job |
| ALB not reachable | ALB still provisioning | Wait 2 min after first deployment; check `kubectl describe ingress` |
