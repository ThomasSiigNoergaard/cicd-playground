# -----------------------------------------------------------------------------
# Elastic Container Registry
# -----------------------------------------------------------------------------

#trivy:ignore:AVD-AWS-0033 Images are encrypted at rest with AES256 (AWS owned key). A customer managed KMS key adds about 1 USD/month plus API costs and is not needed for a lab.
resource "aws_ecr_repository" "this" {
  name = local.name

  # IMMUTABLE tags: once "abc123" is pushed it can never point at different
  # content. Deployments reference images by digest anyway, but immutability
  # also protects the human readable tags from being silently overwritten.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    # Basic scanning on push (free). Amazon Inspector enhanced scanning adds
    # continuous re-scanning and OS + language package coverage for a fee.
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  force_delete = var.ecr_force_delete

  tags = { Name = local.name }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  # Rules are evaluated in rulePriority order (lowest first).
  # Note: the deploy workflow also pushes build provenance and SBOM
  # attestations to ECR as OCI referrer artifacts (they show up as untagged
  # entries). `gh attestation verify` reads from GitHub's attestation store by
  # default, so verification keeps working even after the untagged rule below
  # expires those registry copies.
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.ecr_untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.ecr_untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the ${var.ecr_max_tagged_images} most recent tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.ecr_max_tagged_images
        }
        action = { type = "expire" }
      },
    ]
  })
}
