# ─────────────────────────────────────────────────────────────────────────────
# Makefile — EKS Terraform workflow
#
# USAGE:
#   make bootstrap          # Step 0: create S3 + DynamoDB, wire backend.tf
#   make init               # Step 1: terraform init with S3 backend
#   make plan               # terraform plan (dev)
#   make apply              # full apply in dependency order
#   make destroy            # ordered destroy (bottom-up)
#   make fmt                # format all .tf files
#   make validate           # validate all modules
#   make help               # show this help
# ─────────────────────────────────────────────────────────────────────────────

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Paths
BOOTSTRAP_DIR := infra/bootstrap
DEV_DIR       := infra/environments/dev
BACKEND_FILE  := infra/global/backend.tf

# Colours for output
BOLD  := \033[1m
RESET := \033[0m
GREEN := \033[32m
CYAN  := \033[36m

# ─────────────────────────────────────────────────────────────────────────────

.PHONY: help
help:
	@echo ""
	@printf "$(BOLD)EKS Terraform — Available Targets$(RESET)\n"
	@echo "──────────────────────────────────────────────────────"
	@printf "  $(CYAN)make bootstrap$(RESET)    Run Step 0: create S3 + DynamoDB, auto-wire backend.tf\n"
	@printf "  $(CYAN)make init$(RESET)         terraform init for dev environment (uses S3 backend)\n"
	@printf "  $(CYAN)make plan$(RESET)         terraform plan for dev environment\n"
	@printf "  $(CYAN)make apply$(RESET)        Full apply in dependency order (two-phase)\n"
	@printf "  $(CYAN)make destroy$(RESET)      Ordered destroy (bottom-up, targeted)\n"
	@printf "  $(CYAN)make fmt$(RESET)          terraform fmt across all modules\n"
	@printf "  $(CYAN)make validate$(RESET)     terraform validate across all modules\n"
	@printf "  $(CYAN)make outputs$(RESET)      Show dev environment outputs\n"
	@printf "  $(CYAN)make kubeconfig$(RESET)   Update local kubeconfig for the dev cluster\n"
	@echo ""

# ─── Step 0: Bootstrap ────────────────────────────────────────────────────

.PHONY: bootstrap
bootstrap:
	@echo ""
	@printf "$(BOLD)Step 0 — Bootstrap$(RESET)\n"
	@echo "Creating S3 state bucket and DynamoDB lock table..."
	@echo ""

	@# Init bootstrap with local state (no backend yet)
	cd $(BOOTSTRAP_DIR) && terraform init

	@# Apply bootstrap
	cd $(BOOTSTRAP_DIR) && terraform apply -auto-approve

	@# Wire the outputs into backend.tf automatically
	@$(MAKE) --no-print-directory _wire_backend

	@echo ""
	@printf "$(GREEN)Bootstrap complete.$(RESET)\n"
	@echo "Next: run 'make init' to initialise the dev environment with the S3 backend."
	@echo ""

# Internal target — reads bootstrap outputs and patches backend.tf
.PHONY: _wire_backend
_wire_backend:
	@echo ""
	@echo "Wiring bootstrap outputs into $(BACKEND_FILE)..."
	@bash scripts/wire-backend.sh

# ─── Dev Environment ──────────────────────────────────────────────────────

.PHONY: init
init:
	@echo ""
	@printf "$(BOLD)terraform init — dev$(RESET)\n"
	@# Copy backend config into dev directory before init
	cp $(BACKEND_FILE) $(DEV_DIR)/backend.tf
	cp infra/global/versions.tf $(DEV_DIR)/versions.tf
	cd $(DEV_DIR) && terraform init
	@echo ""

.PHONY: plan
plan: _check_init
	@echo ""
	@printf "$(BOLD)terraform plan — dev$(RESET)\n"
	cd $(DEV_DIR) && terraform plan
	@echo ""

.PHONY: apply
apply: _check_init
	@echo ""
	@printf "$(BOLD)terraform apply — dev (two-phase)$(RESET)\n"
	@echo ""
	@echo "Phase 1: core infrastructure (kms, vpc, security_groups)..."
	cd $(DEV_DIR) && terraform apply \
		-target=module.kms \
		-target=module.vpc \
		-target=module.security_groups \
		-auto-approve
	@echo ""
	@echo "Phase 2: all remaining modules..."
	cd $(DEV_DIR) && terraform apply -auto-approve
	@echo ""
	@printf "$(GREEN)Apply complete.$(RESET)\n"
	@$(MAKE) --no-print-directory outputs
	@echo ""

.PHONY: outputs
outputs: _check_init
	@echo ""
	@printf "$(BOLD)Dev Environment Outputs$(RESET)\n"
	@echo "──────────────────────────────────────────────────────"
	cd $(DEV_DIR) && terraform output
	@echo ""

.PHONY: kubeconfig
kubeconfig: _check_init
	@CLUSTER=$$(cd $(DEV_DIR) && terraform output -raw cluster_name); \
	 REGION=$$(cd $(DEV_DIR) && terraform output -raw aws_region 2>/dev/null || echo "ap-south-1"); \
	 echo "Updating kubeconfig for cluster: $$CLUSTER in $$REGION"; \
	 aws eks update-kubeconfig --name $$CLUSTER --region $$REGION
	@echo ""
	@echo "kubeconfig updated. Test with: kubectl get nodes"
	@echo ""

# ─── Ordered Destroy ──────────────────────────────────────────────────────

.PHONY: destroy
destroy: _check_init
	@echo ""
	@printf "$(BOLD)Ordered destroy — dev$(RESET)\n"
	@echo "This will destroy all resources in reverse dependency order."
	@echo ""
	@read -p "Are you sure? Type 'yes' to continue: " confirm; \
	 if [ "$$confirm" != "yes" ]; then \
	   echo "Aborted."; exit 1; \
	 fi
	@echo ""
	@bash scripts/ordered-destroy.sh
	@echo ""

# ─── Code Quality ─────────────────────────────────────────────────────────

.PHONY: fmt
fmt:
	@echo ""
	@printf "$(BOLD)terraform fmt — all modules$(RESET)\n"
	terraform fmt -recursive infra/
	@echo ""
	@printf "$(GREEN)Formatting complete.$(RESET)\n"
	@echo ""

.PHONY: validate
validate:
	@echo ""
	@printf "$(BOLD)terraform validate — all modules$(RESET)\n"
	@for dir in infra/modules/*/; do \
	  printf "  Validating $$dir... "; \
	  cd $$dir && terraform init -backend=false -no-color > /dev/null 2>&1 \
	    && terraform validate -no-color \
	    && cd - > /dev/null \
	    || (echo "FAILED in $$dir"; exit 1); \
	done
	@echo ""
	@printf "$(GREEN)All modules valid.$(RESET)\n"
	@echo ""

# ─── Guards ───────────────────────────────────────────────────────────────

.PHONY: _check_init
_check_init:
	@if [ ! -f "$(DEV_DIR)/.terraform/terraform.tfstate" ]; then \
	  echo ""; \
	  echo "ERROR: dev environment not initialised. Run 'make init' first."; \
	  echo ""; \
	  exit 1; \
	fi
