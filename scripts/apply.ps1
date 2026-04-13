# apply.ps1 - Full two-phase apply for dev environment
# Phase 1: kms + vpc + security_groups (must exist before EKS references them)
# Phase 2: everything else
# Usage: .\scripts\apply.ps1

$RepoRoot = Split-Path $PSScriptRoot -Parent
$DevDir   = Join-Path $RepoRoot "infra\environments\dev"

Write-Host ""
Write-Host "terraform apply - dev (two-phase)" -ForegroundColor Cyan
Write-Host ""

Push-Location $DevDir

# --- Phase 1: core infrastructure ---
Write-Host "Phase 1: kms, vpc, security_groups..." -ForegroundColor Yellow
Write-Host ""

$phase1 = @("-target=module.kms", "-target=module.vpc", "-target=module.security_groups", "-auto-approve")
terraform apply @phase1

if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Host "ERROR: Phase 1 apply failed." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Phase 1 complete." -ForegroundColor Green

# --- Phase 2: all remaining modules ---
Write-Host ""
Write-Host "Phase 2: all remaining modules..." -ForegroundColor Yellow
Write-Host ""

terraform apply -auto-approve

if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Host "ERROR: Phase 2 apply failed." -ForegroundColor Red
    exit 1
}

Pop-Location

Write-Host ""
Write-Host "Apply complete." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Show outputs (cluster name, Grafana URL, ECR URLs):"
Write-Host "       .\scripts\outputs.ps1"
Write-Host ""
Write-Host "  2. Configure kubectl:"
Write-Host "       .\scripts\kubeconfig.ps1"
Write-Host ""
Write-Host "  3. Verify nodes and pods are ready:"
Write-Host "       kubectl get nodes"
Write-Host "       kubectl get pods -A"
Write-Host ""
Write-Host "  4. Bootstrap ArgoCD (run once after every fresh apply):" -ForegroundColor Yellow
Write-Host "       kubectl apply -f k8s/argocd/app-nodeapp.yaml -n argocd"
Write-Host ""
Write-Host "  5. Watch ArgoCD sync the nodeapp (~30 seconds):"
Write-Host "       kubectl get applications -n argocd"
Write-Host "       kubectl get pods -n nodeapp"
Write-Host ""
Write-Host "  6. Get the ALB URL:"
Write-Host "       kubectl get ingress -n nodeapp"
Write-Host ""
