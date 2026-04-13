# outputs.ps1 - Show dev environment terraform outputs
# Usage: .\scripts\outputs.ps1

$RepoRoot = Split-Path $PSScriptRoot -Parent
$DevDir   = Join-Path $RepoRoot "infra\environments\dev"

Write-Host ""
Write-Host "Dev Environment Outputs" -ForegroundColor Cyan
Write-Host "------------------------------------------------------"

Push-Location $DevDir
terraform output
Pop-Location

Write-Host ""
