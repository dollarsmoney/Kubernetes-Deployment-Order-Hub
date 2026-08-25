###############################################################################
# ecr.tf — private container registries
###############################################################################
#
# Docker Hub would also work, but ECR is the natural choice on EKS:
#   - nodes authenticate with their IAM role (AmazonEC2ContainerRegistryReadOnly)
#     so there is no registry password to manage anywhere
#   - pulls stay inside AWS's network
#   - no Docker Hub rate limits, which WILL bite you on a cluster that
#     restarts pods frequently
#
# Cost: $0.10/GB/month. Our two images total well under 1 GB.
###############################################################################

locals {
  ecr_repos = {
    frontend = "${local.name}/frontend"
    backend  = "${local.name}/backend"
  }
}

resource "aws_ecr_repository" "app" {
  for_each = local.ecr_repos

  name = each.value

  # MUTABLE lets us push :latest repeatedly, which is convenient while
  # learning. Production should use IMMUTABLE so a given tag always means the
  # same bytes — "it worked yesterday with :latest" is not a debuggable state.
  image_tag_mutability = "MUTABLE"

  # Free vulnerability scanning on every push. Results appear in the ECR
  # console under the image digest.
  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.main.arn
  }

  # Let `terraform destroy` delete the repository even when images are still
  # in it. Without this, destroy fails with RepositoryNotEmptyException and you
  # have to delete images by hand. Appropriate for a learning project;
  # dangerous for a real registry.
  force_delete = true

  tags = { Name = "${local.name}-${each.key}" }
}

# -----------------------------------------------------------------------------
# Lifecycle policy — stop old images accumulating forever
# -----------------------------------------------------------------------------
# Every `docker push` of a new :latest leaves the PREVIOUS image untagged but
# still stored and billed. This expires untagged images after a day and caps
# tagged images at 10.
# -----------------------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "app" {
  for_each = aws_ecr_repository.app

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the 10 most recent tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      },
    ]
  })
}
