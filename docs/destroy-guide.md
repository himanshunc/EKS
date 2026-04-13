# Destroy Guide — Ordered Teardown

Always destroy in reverse apply order. Resources that depend on others must be destroyed first.

```bash
cd infra/environments/dev

# 1. Logging (FluentBit, CloudWatch log group, Container Insights)
terraform destroy -target=module.logging

# 2. Monitoring (Prometheus agent, AMP, AMG)
terraform destroy -target=module.monitoring

# 3. ArgoCD
terraform destroy -target=module.argocd

# 4. Helm Addons (ALB controller, Cluster Autoscaler, EBS CSI, NTH)
terraform destroy -target=module.helm_addons

# 5. Cluster Defaults (namespaces, LimitRanges, NetworkPolicies, PDBs)
terraform destroy -target=module.cluster_defaults

# 6. ECR (repositories and lifecycle policies)
terraform destroy -target=module.ecr

# 7. Node Groups (Spot + On-Demand managed node groups)
terraform destroy -target=module.node_groups

# 8. EKS (cluster, OIDC provider, add-ons)
terraform destroy -target=module.eks

# 9. IAM (all roles and policies)
terraform destroy -target=module.iam

# 10. Security Groups
terraform destroy -target=module.security_groups

# 11. VPC (subnets, NAT, IGW, endpoints)
terraform destroy -target=module.vpc

# 12. KMS
terraform destroy -target=module.kms

# Optional: destroy bootstrap (S3 + DynamoDB)
# cd ../../bootstrap && terraform destroy
```

## Notes

- **Never** run `terraform destroy` without `-target` — it destroys everything at once and often fails mid-way due to dependency ordering.
- EKS node groups must be destroyed before the EKS cluster.
- IAM IRSA roles depend on the OIDC provider — destroy IAM after EKS.
- The S3 state bucket has `prevent_destroy = true`. You must remove that lifecycle block before destroying bootstrap.
