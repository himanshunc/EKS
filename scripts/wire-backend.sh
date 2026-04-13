#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# wire-backend.sh
#
# Reads the bootstrap terraform outputs (S3 bucket name, DynamoDB table name)
# and patches infra/global/backend.tf with the real values.
#
# Called automatically by: make bootstrap
# Can also be run manually: bash scripts/wire-backend.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BOOTSTRAP_DIR="${REPO_ROOT}/infra/bootstrap"
BACKEND_FILE="${REPO_ROOT}/infra/global/backend.tf"

# ── Read bootstrap outputs ────────────────────────────────────────────────

echo "Reading bootstrap outputs..."

BUCKET=$(cd "${BOOTSTRAP_DIR}" && terraform output -raw state_bucket_name)
TABLE=$(cd "${BOOTSTRAP_DIR}" && terraform output -raw dynamodb_table_name)
REGION=$(cd "${BOOTSTRAP_DIR}" && terraform output -raw aws_region)

if [[ -z "${BUCKET}" || -z "${TABLE}" || -z "${REGION}" ]]; then
  echo "ERROR: Could not read bootstrap outputs. Did 'terraform apply' succeed in infra/bootstrap/?"
  exit 1
fi

echo "  Bucket : ${BUCKET}"
echo "  Table  : ${TABLE}"
echo "  Region : ${REGION}"

# ── Patch backend.tf ─────────────────────────────────────────────────────

echo ""
echo "Patching ${BACKEND_FILE}..."

# Use sed to replace placeholder values with real outputs.
# The placeholders used in backend.tf are specific enough to be safe to replace.

if [[ "$(uname)" == "Darwin" ]]; then
  # macOS sed requires an empty string after -i
  sed -i '' \
    "s|bucket = \"myapp-terraform-state-<YOUR_ACCOUNT_ID>\"|bucket = \"${BUCKET}\"|" \
    "${BACKEND_FILE}"
  sed -i '' \
    "s|dynamodb_table = \"myapp-terraform-locks\"|dynamodb_table = \"${TABLE}\"|" \
    "${BACKEND_FILE}"
  sed -i '' \
    "s|region = \"ap-south-1\"|region = \"${REGION}\"|" \
    "${BACKEND_FILE}"
else
  # Linux / Git Bash / WSL
  sed -i \
    "s|bucket = \"myapp-terraform-state-<YOUR_ACCOUNT_ID>\"|bucket = \"${BUCKET}\"|" \
    "${BACKEND_FILE}"
  sed -i \
    "s|dynamodb_table = \"myapp-terraform-locks\"|dynamodb_table = \"${TABLE}\"|" \
    "${BACKEND_FILE}"
  sed -i \
    "s|region = \"ap-south-1\"|region = \"${REGION}\"|" \
    "${BACKEND_FILE}"
fi

echo ""
echo "backend.tf updated:"
echo "──────────────────────────────────────────────────────"
grep -E 'bucket|dynamodb_table|region|key|encrypt' "${BACKEND_FILE}" | sed 's/^/  /'
echo "──────────────────────────────────────────────────────"
echo ""
echo "Next step: run 'make init' to initialise the dev environment with this backend."
