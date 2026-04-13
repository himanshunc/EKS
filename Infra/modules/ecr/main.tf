# ─────────────────────────────────────────────────────────────────────────────
# ECR Module — Step 7
# Creates one ECR repository per application with:
#   - Image scanning on push (free, catches known CVEs automatically)
#   - Lifecycle policy: keep last 10 tagged images, expire untagged after 7 days
#
# WHY LIFECYCLE POLICIES?
# Without them, ECR fills up indefinitely. Every push adds an image.
# Keeping the last 10 tagged images gives enough rollback headroom.
# Untagged images are build artefacts that aren't deployed anywhere — safe to expire.
# ─────────────────────────────────────────────────────────────────────────────

# ECR repository — one per application in var.repository_names.
# for_each ensures each app gets its own isolated repository.
resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = "${local.name_prefix}-${each.value}"
  image_tag_mutability = "MUTABLE"  # allows re-tagging (e.g. "latest") — change to IMMUTABLE for stricter prod
  force_delete         = true       # allows destroy even when images exist — safe for dev, remove in prod

  # Scan on push — checks every image against the CVE database (ECR Basic scanning, free).
  # Results visible in the ECR console under "Image scan findings".
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encrypt images at rest using AES256 (AWS-managed).
  # Use KMS for stricter compliance requirements.
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${each.value}"
  })
}

# Lifecycle policy — applied to each repository.
# Rule 1: Expire untagged images after 7 days (build artefacts, failed pushes)
# Rule 2: Keep last 10 tagged images (enough for rollback, limits storage cost)
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        # Rule 1: Expire untagged images after 7 days.
        # Untagged = not referenced by any deployment. Safe to delete.
        rulePriority = 1
        description  = "Expire untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        # Rule 2: Keep only the last 10 images (any tag status).
        # tagStatus = "any" avoids needing a tagPrefixList and covers all tagged images.
        rulePriority = 2
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
