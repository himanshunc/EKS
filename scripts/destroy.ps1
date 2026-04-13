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
}

Pop-Location

Write-Host ""
Write-Host "All modules destroyed." -ForegroundColor Green
Write-Host ""
Write-Host "To destroy bootstrap (S3 + DynamoDB):"
Write-Host "  1. Remove 'prevent_destroy = true' from infra\bootstrap\main.tf"
Write-Host "  2. cd infra\bootstrap && terraform destroy"
Write-Host ""
