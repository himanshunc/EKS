# bootstrap.ps1 - Step 0: Create S3 state bucket + DynamoDB lock table
# Run ONCE before anything else.
# Usage: .\scripts\bootstrap.ps1

$RepoRoot     = Split-Path $PSScriptRoot -Parent
$BootstrapDir = Join-Path $RepoRoot "infra\bootstrap"
$BackendFile  = Join-Path $RepoRoot "infra\global\backend.tf"

Write-Host ""
Write-Host "Step 0 - Bootstrap" -ForegroundColor Cyan
Write-Host "Creating S3 state bucket and DynamoDB lock table..."
Write-Host ""

# --- terraform init ---
Push-Location $BootstrapDir

Write-Host "Running: terraform init" -ForegroundColor Yellow
terraform init
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Host "ERROR: terraform init failed." -ForegroundColor Red
    exit 1
}

# --- terraform apply ---
Write-Host ""
Write-Host "Running: terraform apply" -ForegroundColor Yellow
terraform apply -auto-approve
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Host "ERROR: terraform apply failed." -ForegroundColor Red
    exit 1
}

# --- Read outputs ---
# 2>$null silences terraform's progress/warning stderr so only the value is captured
$Bucket = (terraform output -raw state_bucket_name 2>$null)
$Table  = (terraform output -raw dynamodb_table_name 2>$null)
$Region = (terraform output -raw aws_region 2>$null)

Pop-Location

# --- Validate outputs were read ---
if (-not $Bucket -or -not $Table -or -not $Region) {
    Write-Host ""
    Write-Host "ERROR: Could not read bootstrap outputs." -ForegroundColor Red
    Write-Host "Debug manually:"
    Write-Host "  cd infra\bootstrap"
    Write-Host "  terraform output"
    exit 1
}

Write-Host ""
Write-Host "Bootstrap outputs:" -ForegroundColor Green
Write-Host "  Bucket : $Bucket"
Write-Host "  Table  : $Table"
Write-Host "  Region : $Region"

# --- Patch backend.tf with real values ---
Write-Host ""
Write-Host "Patching $BackendFile..."

$content = Get-Content $BackendFile -Raw
$content = $content -replace 'bucket\s*=\s*"[^"]+"',         "bucket         = `"$Bucket`""
$content = $content -replace 'dynamodb_table\s*=\s*"[^"]+"', "dynamodb_table = `"$Table`""
$content = $content -replace '(?m)^(\s*region\s*=\s*)"[^"]+"', "`${1}`"$Region`""
Set-Content -Path $BackendFile -Value $content -NoNewline

Write-Host ""
Write-Host "backend.tf updated:" -ForegroundColor Green
Write-Host "------------------------------------------------------"
Select-String -Path $BackendFile -Pattern '^\s*(bucket|dynamodb_table|region|key|encrypt)' |
    ForEach-Object { Write-Host "  $($_.Line.Trim())" }
Write-Host "------------------------------------------------------"
Write-Host ""
Write-Host "Bootstrap complete." -ForegroundColor Green
Write-Host "Next: run .\scripts\init.ps1"
Write-Host ""
