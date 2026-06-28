# ─────────────────────────────────────────────────────────────────────────────
# pipeline_build.tf — Pipeline de BUILD
#
# Flux : commit GitHub (branche staging) → CodeBuild → image Docker → ECR
#
# Par application :
#   - S3 bucket pour les artefacts
#   - CodeBuild project : build + push image staging-<sha> et staging-latest
#   - CodePipeline      : Source (GitHub) → Build (CodeBuild)
#
# Le pipeline se déclenche automatiquement sur chaque commit de la branche
# définie dans build_branch (par défaut : "staging").
# ─────────────────────────────────────────────────────────────────────────────

# ── S3 Buckets pour les artefacts de build ────────────────────────────────────

resource "aws_s3_bucket" "pipeline_build_artifacts" {
  for_each = var.apps

  bucket        = "${each.value.name}-build-artifacts-${local.account_id}"
  force_destroy = true

  tags = {
    App = each.value.name
    Use = "pipeline-build-artifacts"
  }
}

resource "aws_s3_bucket_versioning" "pipeline_build_artifacts" {
  for_each = var.apps

  bucket = aws_s3_bucket.pipeline_build_artifacts[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline_build_artifacts" {
  for_each = var.apps

  bucket = aws_s3_bucket.pipeline_build_artifacts[each.key].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "pipeline_build_artifacts" {
  for_each = var.apps

  bucket                  = aws_s3_bucket.pipeline_build_artifacts[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── CodeBuild : Build & Push Image Docker ─────────────────────────────────────

resource "aws_codebuild_project" "build" {
  for_each = var.apps

  name          = "${each.value.name}-build"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 20

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true # requis pour Docker

    environment_variable {
      name  = "ECR_REPO_URL"
      value = aws_ecr_repository.app[each.key].repository_url
    }
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = local.account_id
    }
    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }
    environment_variable {
      name  = "APP_NAME"
      value = each.value.name
    }
  }

  source {
    type = "CODEPIPELINE"
    buildspec = yamlencode({
      version = "0.2"
      phases = {
        pre_build = {
          commands = [
            "echo Logging into Amazon ECR...",
            "aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com",
            "SHORT_SHA=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c1-8)",
            "IMAGE_TAG=staging-$SHORT_SHA",
            "echo Building image with tag: $IMAGE_TAG"
          ]
        }
        build = {
          commands = [
            "docker build -t $ECR_REPO_URL:$IMAGE_TAG -t $ECR_REPO_URL:staging-latest ."
          ]
        }
        post_build = {
          commands = [
            "docker push $ECR_REPO_URL:$IMAGE_TAG",
            "docker push $ECR_REPO_URL:staging-latest",
            "echo Build complete. Image: $ECR_REPO_URL:$IMAGE_TAG",
            "printf '[{\"name\":\"%s\",\"imageUri\":\"%s\"}]' \"$APP_NAME\" \"$ECR_REPO_URL:$IMAGE_TAG\" > imagedefinitions.json"
          ]
        }
      }
      artifacts = { files = ["imagedefinitions.json", "**/*"] }
    })
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${each.value.name}"
      stream_name = "build"
    }
  }

  tags = {
    App = each.value.name
    Use = "build"
  }
}

# ── CodePipeline : Build (déclenchement automatique sur commit staging) ────────

resource "aws_codepipeline" "build" {
  for_each = var.apps

  name     = "${each.value.name}-build-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_build_artifacts[each.key].bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        ConnectionArn    = var.codestar_connection_arn
        FullRepositoryId = each.value.github_repo_id
        BranchName       = each.value.build_branch
        DetectChanges    = "true" # déclenchement auto sur commit
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "BuildAndPush"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      configuration = {
        ProjectName = aws_codebuild_project.build[each.key].name
      }
    }
  }

  tags = {
    App = each.value.name
    Use = "build-pipeline"
  }
}
