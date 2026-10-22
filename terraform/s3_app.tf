# ─────────────────────────────────────────────────────────────────────────────
# s3_app.tf — Buckets S3 applicatifs optionnels (prod + staging) par application
#
# Activé par app via : create_app_bucket = true
#
# Nommage par défaut (app_bucket_name_prod / app_bucket_name_staging vides) :
#   prod    → "<app-name>-prod-data"
#   staging → "<app-name>-staging-data"
#
# Nommage personnalisé : renseigner app_bucket_name_prod et/ou app_bucket_name_staging
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # Apps pour lesquelles create_app_bucket = true
  apps_with_bucket = {
    for k, app in var.apps : k => app
    if app.create_app_bucket
  }

  # Noms effectifs des buckets prod et staging
  app_bucket_names_prod = {
    for k, app in local.apps_with_bucket : k =>
      app.app_bucket_name_prod != "" ? app.app_bucket_name_prod : "${app.name}-prod-data"
  }

  app_bucket_names_staging = {
    for k, app in local.apps_with_bucket : k =>
      app.app_bucket_name_staging != "" ? app.app_bucket_name_staging : "${app.name}-staging-data"
  }
}

# ── Buckets S3 prod ───────────────────────────────────────────────────────────

resource "aws_s3_bucket" "app_prod" {
  for_each = local.apps_with_bucket

  bucket = local.app_bucket_names_prod[each.key]

  tags = {
    Name        = local.app_bucket_names_prod[each.key]
    Application = each.value.name
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "app_prod" {
  for_each = local.apps_with_bucket

  bucket = aws_s3_bucket.app_prod[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "app_prod" {
  for_each = local.apps_with_bucket

  bucket = aws_s3_bucket.app_prod[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_prod" {
  for_each = local.apps_with_bucket

  bucket = aws_s3_bucket.app_prod[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── Buckets S3 staging ────────────────────────────────────────────────────────

resource "aws_s3_bucket" "app_staging" {
  for_each = local.apps_with_bucket

  bucket = local.app_bucket_names_staging[each.key]

  tags = {
    Name        = local.app_bucket_names_staging[each.key]
    Application = each.value.name
    Environment = "staging"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "app_staging" {
  for_each = local.apps_with_bucket

  bucket = aws_s3_bucket.app_staging[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "app_staging" {
  for_each = local.apps_with_bucket

  bucket = aws_s3_bucket.app_staging[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_staging" {
  for_each = local.apps_with_bucket

  bucket = aws_s3_bucket.app_staging[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
