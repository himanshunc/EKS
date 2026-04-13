# kubeconfig.ps1 - Update local kubeconfig for the dev EKS cluster
# Usage: .\scripts\kubeconfig.ps1

$RepoRoot = Split-Path $PSScriptRoot -Parent
$DevDir   = Join-Path $RepoRoot "infra\environments\dev"

Push-Location $DevDir
$ClusterName = (terraform output -raw cluster_name 2>$null)
Pop-Location

if (-not $ClusterName) {
    Write-Host "ERROR: Could not read cluster_name output. Has the cluster been applied?" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Updating kubeconfig for cluster: $ClusterName" -ForegroundColor Cyan

aws eks update-kubeconfig --name $ClusterName --region ap-south-1

Write-Host ""
Write-Host "kubeconfig updated." -ForegroundColor Green
Write-Host "Test with: kubectl get nodes"
Write-Host ""
