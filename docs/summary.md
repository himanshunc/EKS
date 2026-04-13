# EKS GitOps Project — Summary

## Part 1 — What Terraform Built (in order)

```
Bootstrap (manual, once)
│  Creates S3 bucket + DynamoDB table to store Terraform state remotely.
│  Without this, state is local and can't be shared or recovered.
│
├── Step 1: KMS
│   Creates an encryption key. EKS uses it to encrypt Kubernetes Secrets
│   at rest in etcd (the cluster database). Key rotation is automatic.
│
├── Step 2: VPC
│   Your private network in AWS. Creates:
│   - 2 public subnets  (internet-facing ALBs live here)
│   - 2 private subnets (EKS nodes live here, no direct internet access)
│   - NAT Gateway       (nodes use this to reach internet for image pulls)
│   - Internet Gateway  (public subnets route through this)
│   - VPC Endpoints     (S3, ECR, STS, EC2 traffic stays inside AWS network
│                        — faster and avoids NAT charges)
│
├── Step 3: Security Groups
│   Firewalls at the network interface level.
│   - Cluster SG: controls what can talk to the EKS API server
│   - Node SG:    controls what can talk to worker nodes
│
├── Step 4: IAM
│   Identity and permissions.
│   - Cluster role:         EKS control plane assumes this to manage AWS resources
│   - Node role:            EC2 instances assume this to join the cluster, pull ECR images
│   - GitHub Actions role:  CI assumes this via OIDC to push Docker images to ECR
│
├── Step 5: EKS Cluster
│   The Kubernetes control plane (AWS-managed — you never touch these servers).
│   - API server:    accepts kubectl commands
│   - etcd:          stores all cluster state (encrypted with KMS key from Step 1)
│   - OIDC provider: enables IRSA (pods get IAM roles without static credentials)
│   - Audit logs:    every kubectl command is logged to CloudWatch
│
├── Step 6: IRSA (IAM Roles for Service Accounts)
│   Runs AFTER EKS because it needs the OIDC provider URL.
│   Binds IAM roles to specific Kubernetes service accounts:
│   - ALB Controller     → can create/manage Load Balancers
│   - Cluster Autoscaler → can add/remove EC2 nodes
│   - EBS CSI Driver     → can create/attach EBS volumes
│   - Prometheus         → can write metrics to AMP
│   - Grafana            → can query AMP metrics
│
├── Step 7: Node Groups
│   The actual EC2 instances that run your pods.
│   - Spot group:      cheaper (up to 70% off), can be interrupted with 2-min notice
│   - On-demand group: stable, always available, costs more
│   - Instance type:   t3.large (2 vCPU, 8 GB RAM, max 35 pods per node)
│
├── Step 8: ECR + EKS Add-ons
│   - ECR:       private Docker image registry (gitops-dev-api, gitops-dev-frontend, etc.)
│   - CoreDNS:   DNS server inside the cluster (pods find each other by name)
│   - vpc-cni:   gives each pod its own VPC IP address
│   - kube-proxy: handles network routing between pods and services
│
├── Step 9: Cluster Defaults
│   Kubernetes-level safety rails applied to every namespace:
│   - LimitRange:           every pod gets a CPU/memory ceiling (prevents runaway pods)
│   - NetworkPolicy:        default-deny-all (pods can't talk unless explicitly allowed)
│   - PodDisruptionBudget:  during node drains, always keep 1 CoreDNS pod running
│
├── Step 10: Helm Addons
│   Cluster-level tools deployed via Helm:
│   - ALB Controller:          watches Ingress resources → creates AWS ALBs automatically
│   - Metrics Server:          powers kubectl top + Horizontal Pod Autoscaler
│   - Cluster Autoscaler:      adds nodes when pods can't schedule, removes idle nodes
│   - EBS CSI Driver:          lets pods request persistent disk (PVC → EBS volume)
│   - Node Termination Handler: catches Spot interruption notices, drains node gracefully
│
├── Step 11: ArgoCD
│   GitOps controller. Watches your GitHub repo and syncs the cluster to match.
│   Exposed via ALB Ingress — open the UI in a browser.
│
├── Step 12: Monitoring
│   - AMP (Amazon Managed Prometheus): receives and stores metrics
│   - Prometheus Agent (Helm):         scrapes all pods → forwards to AMP
│   - Grafana (Helm):                  dashboards, queries in-cluster Prometheus
│   - Alert rules in AMP:              fires on high CPU, OOMKill, pods not running
│
└── Step 13: Logging
    - FluentBit (Helm):      reads container logs from every node → ships to CloudWatch
    - CloudWatch Log Group:  /aws/eks/gitops-dev-eks-cluster/containers
    - Container Insights:    enhanced pod-level metrics in CloudWatch
```

---

## Part 2 — How a Request Reaches Your App

```
Browser
  │
  ▼
AWS ALB  (created by ALB Controller when it saw the Ingress resource)
  │
  ├── /api/*  ──► api Service (ClusterIP) ──► api Pod (port 8080)
  │
  └── /*      ──► frontend Service (ClusterIP) ──► frontend Pod (port 80)

The ALB talks directly to pod IPs (target-type: ip).
NetworkPolicy allows inbound traffic from the VPC CIDR (10.0.0.0/16).
```

---

## Part 3 — How Apps Get Deployed (CI/CD Flow)

```
You edit apps/api/main.go and push to main
         │
         ▼
GitHub Actions detects push (path: apps/api/**)
         │
         ├── 1. Authenticates to AWS via OIDC
         │        GitHub mints a short-lived token
         │        AWS exchanges it for temporary credentials (no static keys)
         │
         ├── 2. Logs into ECR
         │
         ├── 3. docker build  →  tags image as gitops-dev-api:a1b2c3d (git SHA)
         │
         ├── 4. docker push   →  image lands in ECR
         │
         ├── 5. Updates k8s/apps/api/deployment.yaml
         │        image: 500849274222.dkr.ecr.ap-south-1.amazonaws.com/gitops-dev-api:a1b2c3d
         │
         └── 6. git commit + git push  →  manifest change lands in GitHub
                  │
                  ▼
         ArgoCD polls GitHub every 3 minutes (or you click Refresh)
                  │
                  ├── Detects: deployment.yaml changed
                  │
                  └── kubectl apply → Kubernetes rolling update
                           │
                           ├── Starts new pod with new image
                           ├── Waits for readiness probe to pass
                           ├── Shifts traffic to new pod
                           └── Terminates old pod
                           (zero downtime — maxUnavailable: 0)
```

---

## Part 4 — Key Concepts in One Line Each

| Concept | What it does |
|---|---|
| **IRSA** | Pods get AWS permissions without any passwords — uses the cluster's OIDC identity |
| **GitOps** | Git is the source of truth — the cluster always matches what's in the repo |
| **Spot instances** | Cheap nodes that AWS can reclaim with 2-min notice — NTH drains them gracefully |
| **VPC Endpoints** | ECR/S3/STS traffic stays inside AWS — no NAT charges, lower latency |
| **NetworkPolicy** | Default-deny firewall between pods — each service explicitly allows only what it needs |
| **LimitRange** | Prevents any single pod from starving others by consuming all node CPU/memory |
| **PDB** | During maintenance, Kubernetes won't drain a node if it would take a critical pod down |
| **ALB target-type: ip** | Load balancer routes directly to pod IPs — no extra NodePort hop |
| **ArgoCD self-heal** | If someone manually changes something with kubectl, ArgoCD reverts it within minutes |
