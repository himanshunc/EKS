## Description
<!-- What does this change do? Why is it needed? -->

## Module(s) Changed
<!-- List each module touched (e.g. vpc, iam, eks) -->

## Checklist

### Terraform
- [ ] `terraform fmt` passes (no formatting errors)
- [ ] `terraform validate` passes
- [ ] `terraform plan` reviewed — no unexpected destroys
- [ ] No hardcoded account IDs, regions, CIDRs, or ARNs
- [ ] All new variables have `description` and `type`
- [ ] All new outputs have `description`
- [ ] All new `.tfvars` variables have a comment above them
- [ ] `locals.tf` used for computed names (not inline in `main.tf`)

### Security
- [ ] KMS key rotation is `true` (never disabled)
- [ ] No secrets in `.tfvars` (use SSM or Secrets Manager)
- [ ] Audit logs still enabled: `api`, `audit`, `authenticator`
- [ ] VPC endpoints not removed (S3, ECR, STS, EC2)
- [ ] Node Termination Handler not removed

### Dependencies
- [ ] `depends_on` in `environments/dev/main.tf` is correct
- [ ] Destroy order in docs/destroy-guide.md is still valid

## Destroy Order Impact
<!-- Will this change affect how resources must be destroyed? Update destroy-guide.md if yes -->

## Cost Impact
<!-- Any new resources? Approximate monthly cost? -->
