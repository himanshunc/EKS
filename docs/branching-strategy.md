# Branching Strategy

## Branch Structure

```
main          ← production-ready, protected, requires PR + approval
  │
  └── develop ← integration branch, all features merge here first
        │
        └── feature/vpc-endpoints
        └── feature/monitoring-amp
        └── feature/node-termination-handler
        └── fix/kms-key-rotation
```

## Branch Protection Rules

| Branch | Required PR | Approvals | CI must pass | Direct push |
|---|---|---|---|---|
| `main` | Yes | 1 | Yes | No |
| `develop` | Yes | 0 | Yes | No |
| `feature/*` | No | — | — | Yes |
| `fix/*` | No | — | — | Yes |

## PR Flow

```
feature/* → develop (PR + review) → main (PR + approval + CI green)
```

## GitHub Actions Triggers

| Workflow | Trigger |
|---|---|
| `terraform-plan.yml` | PR to `develop` or `main` (paths: infra/**) |
| `terraform-apply.yml` | Push/merge to `main` (paths: infra/**) |

## Commit Message Convention

```
<type>(<scope>): <short description>

type:  feat | fix | refactor | docs | chore
scope: module name (e.g. vpc, eks, iam, monitoring)

Examples:
  feat(vpc): add VPC endpoints for S3 and ECR
  fix(iam): scope cluster-autoscaler permissions to cluster
  docs(monitoring): add Grafana dashboard import instructions
```
