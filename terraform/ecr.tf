# ─────────────────────────────────────────────────────────────────────────────
# ecr.tf — Repos ECR
# Un repo est créé par app sauf si ecr_repo_key est renseigné,
# auquel cas l'app partage le repo de l'app désignée.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "app" {
  # Ne crée un repo que pour les apps sans ecr_repo_key
  for_each = { for k, v in var.apps : k => v if v.ecr_repo_key == "" }

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
  for_each = { for k, v in var.apps : k => v if v.ecr_repo_key == "" }

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

locals {
  # Résout l'URL ECR pour chaque app :
  # - Si ecr_repo_key est vide → repo propre à l'app
  # - Sinon → repo de l'app désignée par ecr_repo_key
  ecr_repo_urls = {
    for k, v in var.apps : k =>
      v.ecr_repo_key == ""
        ? aws_ecr_repository.app[k].repository_url
        : aws_ecr_repository.app[v.ecr_repo_key].repository_url
  }
}
