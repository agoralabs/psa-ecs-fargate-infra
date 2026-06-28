# ─────────────────────────────────────────────────────────────────────────────
# ecr.tf — Repos ECR, un par application
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "app" {
  for_each = var.apps

  name                 = each.value.name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = each.value.name
    App  = each.value.name
  }
}

# Lifecycle policy : conserver les 20 dernières images
resource "aws_ecr_lifecycle_policy" "app" {
  for_each = var.apps

  repository = aws_ecr_repository.app[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 20 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 20
        }
        action = { type = "expire" }
      }
    ]
  })
}
