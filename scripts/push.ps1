# push.ps1 - Safe push that handles CI manifest commits automatically.
# Usage: .\scripts\push.ps1
#
# Why this exists:
#   The CI pipeline commits a manifest update back to main after every build.
#   This puts your local branch 1 commit behind remote, causing push to fail.
#   This script always pulls with rebase first so you never hit that error.

$branch = git rev-parse --abbrev-ref HEAD

if ($branch -ne "main") {
    Write-Host "Not on main branch (currently on: $branch)" -ForegroundColor Red
    Write-Host "Switch to main first: git checkout main"
    exit 1
}

Write-Host "Pulling latest (rebase)..." -ForegroundColor Cyan
git pull --rebase origin main
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: rebase failed - resolve conflicts then run again." -ForegroundColor Red
    exit 1
}

Write-Host "Pushing..." -ForegroundColor Cyan
git push origin main
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: push failed." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Pushed. CI will trigger if apps/nodeapp/** changed." -ForegroundColor Green
Write-Host "Watch actions: https://github.com/himanshunc/EKS/actions"
Write-Host ""
