# ─────────────────────────────────────────────────────────────────────────────
# pipeline_deploy.tf — Pipelines de DÉPLOIEMENT par environnement
#
# Un pipeline par application par environnement (staging et prod).
# Déclenchement MANUEL avec paramètre IMAGE_TAG.
#
# Pipelines créés :
#   - <app>-staging-pipeline : déploie sur ECS staging avec IMAGE_TAG donné
#   - <app>-prod-pipeline    : déploie sur ECS prod avec IMAGE_TAG donné
#
# Flux :
#   Source (GitHub, DetectChanges=false) → Deploy (CodeBuild update-service)
# ─────────────────────────────────────────────────────────────────────────────

# ── S3 Buckets pour les artefacts de déploiement ─────────────────────────────

resource "aws_s3_bucket" "pipeline_deploy_artifacts" {
  for_each = var.apps

  bucket        = "${each.value.name}-deploy-artifacts-${local.account_id}"
  force_destroy = true

  tags = {
    App = each.value.name
    Use = "pipeline-deploy-artifacts"
  }
}

resource "aws_s3_bucket_versioning" "pipeline_deploy_artifacts" {
  for_each = var.apps

  bucket = aws_s3_bucket.pipeline_deploy_artifacts[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline_deploy_artifacts" {
  for_each = var.apps

  bucket = aws_s3_bucket.pipeline_deploy_artifacts[each.key].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "pipeline_deploy_artifacts" {
  for_each = var.apps

  bucket                  = aws_s3_bucket.pipeline_deploy_artifacts[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─────────────────────────────────────────────────────────────────────────────
# CodeBuild — Deploy Staging
# Met à jour la task definition ECS staging avec l'IMAGE_TAG passé en paramètre
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_codebuild_project" "deploy_staging" {
  for_each = var.apps

  name          = "${each.value.name}-staging-deploy"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 10

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false

    environment_variable {
      name  = "ECR_REPO_URL"
      value = local.ecr_repo_urls[each.key]
    }
    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }
    environment_variable {
      name  = "ECS_CLUSTER"
      value = aws_ecs_cluster.main.name
    }
    environment_variable {
      name  = "ECS_SERVICE"
      value = aws_ecs_service.staging[each.key].name
    }
    environment_variable {
      name  = "TASK_FAMILY"
      value = "${each.value.name}-staging"
    }
    environment_variable {
      name  = "CONTAINER_NAME"
      value = "${each.value.name}-staging"
    }
    environment_variable {
      name  = "EXECUTION_ROLE_ARN"
      value = aws_iam_role.ecs_task_execution.arn
    }
    environment_variable {
      name  = "TASK_ROLE_ARN"
      value = aws_iam_role.ecs_task.arn
    }
    # Valeur par défaut — sera surchargée par le paramètre du pipeline
    environment_variable {
      name  = "IMAGE_TAG"
      value = "staging-latest"
    }
  }

  source {
    type = "CODEPIPELINE"
    buildspec = yamlencode({
      version = "0.2"
      phases = {
        build = {
          commands = [
            "echo Deploying $ECR_REPO_URL:$IMAGE_TAG to staging ECS service $ECS_SERVICE",
            "aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $AWS_DEFAULT_REGION --query 'taskDefinition' --output json > task-def.json",
            "python3 -c \"\nimport json\ntd = json.load(open('task-def.json'))\nimport os\nimage_tag = os.environ['IMAGE_TAG']\necr_url   = os.environ['ECR_REPO_URL']\ntd['containerDefinitions'][0]['image'] = f'{ecr_url}:{image_tag}'\nenvs = td['containerDefinitions'][0].get('environment', [])\nenvs = [e for e in envs if e['name'] not in ('IMAGE_TAG', 'ENVIRONMENT')]\nenvs.append({'name': 'IMAGE_TAG',    'value': image_tag})\nenvs.append({'name': 'ENVIRONMENT',  'value': 'staging'})\ntd['containerDefinitions'][0]['environment'] = envs\n[td.pop(k, None) for k in ['taskDefinitionArn','revision','status','requiresAttributes','compatibilities','registeredAt','registeredBy','deregisteredAt']]\njson.dump(td, open('new-task-def.json','w'))\n\"",
            "NEW_TASK_DEF_ARN=$(aws ecs register-task-definition --region $AWS_DEFAULT_REGION --cli-input-json file://new-task-def.json --query 'taskDefinition.taskDefinitionArn' --output text)",
            "aws ecs update-service --cluster $ECS_CLUSTER --service $ECS_SERVICE --task-definition $NEW_TASK_DEF_ARN --region $AWS_DEFAULT_REGION",
            "echo Staging deploy triggered for image: $IMAGE_TAG"
          ]
        }
      }
      artifacts = { files = ["**/*"] }
    })
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${each.value.name}"
      stream_name = "staging-deploy"
    }
  }

  tags = {
    App = each.value.name
    Env = "staging"
    Use = "deploy"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# CodeBuild — Deploy Production
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_codebuild_project" "deploy_prod" {
  for_each = var.apps

  name          = "${each.value.name}-prod-deploy"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 10

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false

    environment_variable {
      name  = "ECR_REPO_URL"
      value = local.ecr_repo_urls[each.key]
    }
    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }
    environment_variable {
      name  = "ECS_CLUSTER"
      value = aws_ecs_cluster.main.name
    }
    environment_variable {
      name  = "ECS_SERVICE"
      value = aws_ecs_service.prod[each.key].name
    }
    environment_variable {
      name  = "TASK_FAMILY"
      value = "${each.value.name}-prod"
    }
    environment_variable {
      name  = "CONTAINER_NAME"
      value = each.value.name
    }
    environment_variable {
      name  = "EXECUTION_ROLE_ARN"
      value = aws_iam_role.ecs_task_execution.arn
    }
    environment_variable {
      name  = "TASK_ROLE_ARN"
      value = aws_iam_role.ecs_task.arn
    }
    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
    }
  }

  source {
    type = "CODEPIPELINE"
    buildspec = yamlencode({
      version = "0.2"
      phases = {
        build = {
          commands = [
            "echo Deploying $ECR_REPO_URL:$IMAGE_TAG to production ECS service $ECS_SERVICE",
            "aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $AWS_DEFAULT_REGION --query 'taskDefinition' --output json > task-def.json",
            "python3 -c \"\nimport json\ntd = json.load(open('task-def.json'))\nimport os\nimage_tag = os.environ['IMAGE_TAG']\necr_url   = os.environ['ECR_REPO_URL']\ntd['containerDefinitions'][0]['image'] = f'{ecr_url}:{image_tag}'\nenvs = td['containerDefinitions'][0].get('environment', [])\nenvs = [e for e in envs if e['name'] not in ('IMAGE_TAG', 'ENVIRONMENT')]\nenvs.append({'name': 'IMAGE_TAG',    'value': image_tag})\nenvs.append({'name': 'ENVIRONMENT',  'value': 'production'})\ntd['containerDefinitions'][0]['environment'] = envs\n[td.pop(k, None) for k in ['taskDefinitionArn','revision','status','requiresAttributes','compatibilities','registeredAt','registeredBy','deregisteredAt']]\njson.dump(td, open('new-task-def.json','w'))\n\"",
            "NEW_TASK_DEF_ARN=$(aws ecs register-task-definition --region $AWS_DEFAULT_REGION --cli-input-json file://new-task-def.json --query 'taskDefinition.taskDefinitionArn' --output text)",
            "aws ecs update-service --cluster $ECS_CLUSTER --service $ECS_SERVICE --task-definition $NEW_TASK_DEF_ARN --region $AWS_DEFAULT_REGION",
            "echo Production deploy triggered for image: $IMAGE_TAG"
          ]
        }
      }
      artifacts = { files = ["**/*"] }
    })
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${each.value.name}"
      stream_name = "prod-deploy"
    }
  }

  tags = {
    App = each.value.name
    Env = "prod"
    Use = "deploy"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# CodePipeline — Deploy Staging (manuel, paramètre IMAGE_TAG)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_codepipeline" "deploy_staging" {
  for_each = var.apps

  name          = "${each.value.name}-staging-pipeline"
  role_arn      = aws_iam_role.codepipeline.arn
  pipeline_type = "V2"

  variable {
    name          = "IMAGE_TAG"
    default_value = "staging-latest"
    description   = "Tag ECR à déployer en staging (ex: staging-a1b2c3d4)"
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
        DetectChanges    = "false" # déclenchement MANUEL uniquement
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "DeployToStaging"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]
      configuration = {
        ProjectName = aws_codebuild_project.deploy_staging[each.key].name
        EnvironmentVariables = jsonencode([
          {
            name  = "IMAGE_TAG"
            value = "#{variables.IMAGE_TAG}"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  tags = {
    App = each.value.name
    Env = "staging"
    Use = "deploy-pipeline"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# CodePipeline — Deploy Production (manuel, paramètre IMAGE_TAG)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_codepipeline" "deploy_prod" {
  for_each = var.apps

  name          = "${each.value.name}-prod-pipeline"
  role_arn      = aws_iam_role.codepipeline.arn
  pipeline_type = "V2"

  variable {
    name          = "IMAGE_TAG"
    default_value = "staging-latest"
    description   = "Tag ECR à déployer en production (ex: staging-a1b2c3d4 ou v1.2.0)"
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
        DetectChanges    = "false" # déclenchement MANUEL uniquement
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "DeployToProduction"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]
      configuration = {
        ProjectName = aws_codebuild_project.deploy_prod[each.key].name
        EnvironmentVariables = jsonencode([
          {
            name  = "IMAGE_TAG"
            value = "#{variables.IMAGE_TAG}"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  tags = {
    App = each.value.name
    Env = "prod"
    Use = "deploy-pipeline"
  }
}
