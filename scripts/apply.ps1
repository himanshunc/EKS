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
Write-Host "  Show outputs  : .\scripts\outputs.ps1"
Write-Host "  Setup kubectl : .\scripts\kubeconfig.ps1"
Write-Host ""
