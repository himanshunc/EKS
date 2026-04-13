# fmt.ps1 - terraform fmt across all modules and environments
# Usage: .\scripts\fmt.ps1

$RepoRoot = Split-Path $PSScriptRoot -Parent

Write-Host ""
Write-Host "terraform fmt - all modules" -ForegroundColor Cyan

Push-Location $RepoRoot
terraform fmt -recursive infra/
$exit = $LASTEXITCODE
Pop-Location

if ($exit -ne 0) {
    Write-Host "ERROR: terraform fmt failed." -ForegroundColor Red
    exit 1
}

Write-Host "Formatting complete." -ForegroundColor Green
Write-Host ""
