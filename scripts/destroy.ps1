# destroy.ps1 - Ordered destroy for dev environment (reverse dependency order)
# Usage: .\scripts\destroy.ps1

$RepoRoot = Split-Path $PSScriptRoot -Parent
$DevDir   = Join-Path $RepoRoot "infra\environments\dev"

Write-Host ""
Write-Host "Ordered destroy - dev environment" -ForegroundColor Yellow
Write-Host "This will destroy all resources in reverse dependency order."
Write-Host ""
$confirm = Read-Host "Type 'yes' to continue"
if ($confirm -ne "yes") {
    Write-Host "Aborted." -ForegroundColor Red
    exit 1
}

$Modules = @(
    "logging",
    "monitoring",
    "argocd",
    "helm_addons",
    "cluster_defaults",
    "eks_addons",
    "ecr",
    "node_groups",
    "irsa",
    "eks",
    "iam",
    "security_groups",
    "vpc",
    "kms"
)

Push-Location $DevDir

# ── Pre-destroy: strip ArgoCD Application finalizers ─────────────────────────
# ArgoCD Application objects have a finalizer (resources-finalizer.argocd.argoproj.io)
# that tells ArgoCD to delete managed resources before the Application is removed.
# When ArgoCD is destroyed, the controller dies first — the finalizer can never be
# processed — and the namespace hangs in Terminating forever.
# Strip finalizers here before any module is destroyed.
Write-Host ""
Write-Host "Pre-destroy: stripping ArgoCD Application finalizers..." -ForegroundColor Cyan
kubectl get applications -n argocd -o name 2>$null | ForEach-Object {
    kubectl patch $_ -n argocd --type=json `
        -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>$null
}
Write-Host "Done." -ForegroundColor Green

# ── Pre-destroy: remove EKS access entries (standalone resources in main.tf) ──
# These are not inside any module so the module loop won't catch them.
# Destroy them first (before eks module) to avoid dependency errors.
Write-Host ""
Write-Host "Destroying EKS access entries..." -ForegroundColor Yellow
terraform destroy `
    -target="aws_eks_access_policy_association.github_actions_terraform" `
    -target="aws_eks_access_entry.github_actions_terraform" `
    -auto-approve
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Host "ERROR: Failed to destroy EKS access entries" -ForegroundColor Red
    exit 1
}
Write-Host "Done." -ForegroundColor Green

foreach ($mod in $Modules) {
    Write-Host ""
    Write-Host "Destroying module.$mod..." -ForegroundColor Yellow
    terraform destroy -target="module.$mod" -auto-approve
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        Write-Host "ERROR: Failed to destroy module.$mod" -ForegroundColor Red
        exit 1
    }
    Write-Host "Done: module.$mod" -ForegroundColor Green

    # After ArgoCD is destroyed:
    #   - Delete the argocd namespace (Helm's create_namespace=true creates it but
    #     helm uninstall does NOT delete it — leftover CRDs cause stuck Terminating)
    #   - Delete app namespaces that ArgoCD created (nodeapp etc.) — Terraform does
    #     not manage these so they must be cleaned up manually before the cluster goes.
    if ($mod -eq "argocd") {
        Write-Host "Deleting argocd namespace..." -ForegroundColor Cyan
        kubectl delete namespace argocd --ignore-not-found=true --timeout=60s 2>$null
        Write-Host "Deleting app namespaces created by ArgoCD..." -ForegroundColor Cyan
        kubectl delete namespace nodeapp --ignore-not-found=true --timeout=60s 2>$null
        Write-Host "Done." -ForegroundColor Green
    }
}

Pop-Location

# ── Post-destroy: delete AWS-auto-created CloudWatch log groups ───────────────
# EKS creates /aws/eks/<cluster>/cluster automatically — Terraform never manages
# these so they survive destroy. Delete them explicitly.
Write-Host ""
Write-Host "Cleaning up CloudWatch log groups..." -ForegroundColor Cyan
$LogGroups = aws logs describe-log-groups `
    --log-group-name-prefix "/aws/eks" `
    --query "logGroups[*].logGroupName" `
    --output text --region ap-south-1 2>$null
if ($LogGroups) {
    $LogGroups -split "`t" | ForEach-Object {
        if ($_) {
            Write-Host "  Deleting log group: $_"
            aws logs delete-log-group --log-group-name $_ --region ap-south-1 2>$null
        }
    }
}
Write-Host "Done." -ForegroundColor Green

Write-Host ""
Write-Host "All modules destroyed." -ForegroundColor Green
Write-Host ""
Write-Host "To destroy bootstrap (S3 + DynamoDB):"
Write-Host "  1. Remove 'prevent_destroy = true' from infra\bootstrap\main.tf"
Write-Host "  2. cd infra\bootstrap && terraform destroy"
Write-Host ""
