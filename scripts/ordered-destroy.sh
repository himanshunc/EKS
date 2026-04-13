#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# ordered-destroy.sh
#
# Destroys dev environment resources in reverse dependency order.
# Each module is destroyed with -target so Terraform resolves only that
# module's dependencies — avoids failures from partial state.
#
# Called by: make destroy
# Can also be run manually: bash scripts/ordered-destroy.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_DIR="$(cd "${SCRIPT_DIR}/../infra/environments/dev" && pwd)"

# Helper — destroy a single module target and print progress
destroy_module() {
  local module=$1
  echo ""
  echo "── Destroying module.${module} ──────────────────────────────────"
  cd "${DEV_DIR}" && terraform destroy \
    -target="module.${module}" \
    -auto-approve
  echo "   Done: module.${module}"
}

echo ""
echo "Starting ordered destroy — reverse dependency order"
echo "This will take several minutes."
echo ""

# Destroy order: bottom-up (reverse of apply order)
destroy_module "logging"
destroy_module "monitoring"
destroy_module "argocd"
destroy_module "helm_addons"
destroy_module "cluster_defaults"
destroy_module "ecr"
destroy_module "node_groups"
destroy_module "eks"
destroy_module "iam"
destroy_module "security_groups"
destroy_module "vpc"
destroy_module "kms"

echo ""
echo "All modules destroyed."
echo ""
echo "To destroy bootstrap (S3 + DynamoDB), run:"
echo "  cd infra/bootstrap && terraform destroy"
echo ""
echo "NOTE: The S3 bucket has prevent_destroy = true."
echo "Remove that lifecycle block from infra/bootstrap/main.tf before destroying bootstrap."
