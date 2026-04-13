# Architecture Overview

## Network

```
Internet
    │
    ▼
Internet Gateway
    │
    ├── Public Subnets (ap-south-1a, ap-south-1b)
    │       └── NAT Gateway (single in dev, per-AZ in prod)
    │       └── Internet-facing ALBs
    │
    └── Private Subnets (ap-south-1a, ap-south-1b)
            └── EKS Worker Nodes
            └── Internal ALBs
            └── VPC Endpoints (S3, ECR API, ECR DKR, STS, EC2)
```

## EKS

- Control plane managed by AWS (endpoint: public + private)
- Secrets encrypted with KMS (key rotation enabled)
- Audit logs → CloudWatch: `api`, `audit`, `authenticator`
- OIDC provider → enables IRSA for all add-ons

## Node Groups

| Group | Type | Instance | Purpose |
|---|---|---|---|
| spot | SPOT | t3.medium, t3.large | Primary workloads |
| on-demand | ON_DEMAND | t3.medium | Critical/stateful workloads |

## Observability Stack

```
EKS Pods → Prometheus Agent (Helm) → AMP Workspace
                                            │
FluentBit (DaemonSet) → CloudWatch ────────┤
                                            ▼
                                  Amazon Managed Grafana
                                  ├── AMP (metrics)
                                  └── CloudWatch (logs)
```

## Security

- IRSA everywhere — no static AWS credentials in pods
- KMS rotation enabled for EKS secrets
- IMDSv2 enforced on all nodes (blocks SSRF from pods)
- Default-deny NetworkPolicy per namespace
- VPC endpoints — AWS API traffic stays off the internet
