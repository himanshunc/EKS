# init.ps1 - terraform init for dev environment (uses S3 backend)
# Run after bootstrap.ps1.
# Usage: .\scripts\init.ps1

$RepoRoot    = Split-Path $PSScriptRoot -Parent
$DevDir      = Join-Path $RepoRoot "infra\environments\dev"
$BackendSrc  = Join-Path $RepoRoot "infra\global\backend.tf"
$VersionsSrc = Join-Path $RepoRoot "infra\global\versions.tf"

Write-Host ""
$ProvidersSrc = Join-Path $RepoRoot "infra\global\providers.tf"

Write-Host "Copying backend.tf, versions.tf and providers.tf into dev environment..." -ForegroundColor Cyan
Copy-Item $BackendSrc   (Join-Path $DevDir "backend.tf")   -Force
Copy-Item $VersionsSrc  (Join-Path $DevDir "versions.tf")  -Force
Copy-Item $ProvidersSrc (Join-Path $DevDir "providers.tf") -Force

Write-Host "Running terraform init..." -ForegroundColor Cyan
Write-Host ""

Push-Location $DevDir
terraform init
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Host "ERROR: terraform init failed." -ForegroundColor Red
    exit 1
}
Pop-Location

Write-Host ""
Write-Host "Init complete." -ForegroundColor Green
Write-Host "Next: run .\scripts\plan.ps1 to review changes before applying."
Write-Host ""
