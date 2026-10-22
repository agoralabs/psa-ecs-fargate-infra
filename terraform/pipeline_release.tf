# ─────────────────────────────────────────────────────────────────────────────
# pipeline_release.tf — Pipeline de RELEASE (retag ECR uniquement)
#
# Déclenchement MANUEL avec deux paramètres :
#   - SOURCE_TAG      : tag ECR source à promouvoir (défaut : staging-latest)
#   - RELEASE_VERSION : version cible              (défaut : v1.0.0)
#
# Flux :
#   Source (GitHub, DetectChanges=false) → TagDocker (CodeBuild retag ECR)
#
# Pipeline créé : <app>-release-pipeline
# ─────────────────────────────────────────────────────────────────────────────

# ── CodeBuild : Tag Docker ────────────────────────────────────────────────────

resource "aws_codebuild_project" "tag_docker" {
  for_each = { for k, v in var.apps : k => v if v.enable_release_pipeline }

  name          = "${each.value.name}-tag-docker"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 10

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "ECR_REPO_URL"
      value = local.ecr_repo_urls[each.key]
    }
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = local.account_id
    }
    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }
    # Valeurs par défaut — surchargées par les variables du pipeline
    environment_variable {
      name  = "SOURCE_TAG"
      value = "staging-latest"
    }
    environment_variable {
      name  = "RELEASE_VERSION"
      value = "v1.0.0"
    }
  }

  source {
    type = "CODEPIPELINE"
    buildspec = yamlencode({
      version = "0.2"
      phases = {
        pre_build = {
          commands = [
            "echo Logging into ECR...",
            "aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com",
            "echo Retagging $ECR_REPO_URL:$SOURCE_TAG as $ECR_REPO_URL:$RELEASE_VERSION"
          ]
        }
        build = {
          commands = [
            "docker pull $ECR_REPO_URL:$SOURCE_TAG",
            "docker tag  $ECR_REPO_URL:$SOURCE_TAG $ECR_REPO_URL:$RELEASE_VERSION",
            "docker push $ECR_REPO_URL:$RELEASE_VERSION",
            "echo ECR tag $RELEASE_VERSION created from $SOURCE_TAG"
          ]
        }
      }
      artifacts = { files = ["**/*"] }
    })
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${each.value.name}"
      stream_name = "tag-docker"
    }
  }

  tags = {
    App = each.value.name
    Use = "release"
  }
}

# ── CodePipeline : Release (manuel) ──────────────────────────────────────────

resource "aws_codepipeline" "release" {
  for_each = { for k, v in var.apps : k => v if v.enable_release_pipeline }

  name          = "${each.value.name}-release-pipeline"
  role_arn      = aws_iam_role.codepipeline.arn
  pipeline_type = "V2"

  variable {
    name          = "SOURCE_TAG"
    default_value = "staging-latest"
    description   = "Tag ECR source a promouvoir (ex: staging-a1b2c3d4 ou staging-latest)"
  }

  variable {
    name          = "RELEASE_VERSION"
    default_value = "v1.0.0"
    description   = "Version de release a creer dans ECR (ex: v1.2.3)"
  }

  artifact_store {
    location = aws_s3_bucket.pipeline_deploy_artifacts[each.key].bucket
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
        DetectChanges    = "false"
      }
    }
  }

  stage {
    name = "TagDocker"
    action {
      name            = "TagECRImage"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]
      configuration = {
        ProjectName = aws_codebuild_project.tag_docker[each.key].name
        EnvironmentVariables = jsonencode([
          { name = "SOURCE_TAG",      value = "#{variables.SOURCE_TAG}",      type = "PLAINTEXT" },
          { name = "RELEASE_VERSION", value = "#{variables.RELEASE_VERSION}", type = "PLAINTEXT" }
        ])
      }
    }
  }

  tags = {
    App = each.value.name
    Use = "release-pipeline"
  }
}
