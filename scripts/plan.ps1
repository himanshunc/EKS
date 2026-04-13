# plan.ps1 - terraform plan for dev environment
# Usage: .\scripts\plan.ps1

$RepoRoot = Split-Path $PSScriptRoot -Parent
$DevDir   = Join-Path $RepoRoot "infra\environments\dev"

Write-Host ""
Write-Host "terraform plan - dev" -ForegroundColor Cyan
Write-Host ""

Push-Location $DevDir
terraform plan
$exit = $LASTEXITCODE
Pop-Location

if ($exit -ne 0) {
    Write-Host "ERROR: terraform plan failed." -ForegroundColor Red
    exit 1
}
