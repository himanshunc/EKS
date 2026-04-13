# ─────────────────────────────────────────────────────────────────────────────
# Remote State Backend — S3 + DynamoDB
#
# HOW TO USE:
#   1. Run infra/bootstrap/ first (terraform apply)
#   2. Copy the outputs into the values below
#   3. Run `terraform init` in infra/environments/dev (or prod)
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  backend "s3" {
    # S3 bucket name — from bootstrap output: state_bucket_name
    bucket         = "myapp-terraform-state-500849274222"

    # State file path — one per environment, keeps state isolated
    key = "envs/dev/terraform.tfstate"

    # Region — must match where the bootstrap bucket was created
    region = "ap-south-1"

    # DynamoDB table — from bootstrap output: dynamodb_table_name
    dynamodb_table = "myapp-terraform-locks"

    # Encrypt state at rest in S3 — always true
    encrypt = true
  }
}
