# ─────────────────────────────────────────────────────────────────────────────
# ecs_tasks.tf — Task Definitions & Services ECS Fargate
# Une task definition et un service par application par environnement.
# ─────────────────────────────────────────────────────────────────────────────

# ── CloudWatch Log Groups ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "prod" {
  for_each = var.apps

  name              = "/ecs/${each.value.name}-prod"
  retention_in_days = each.value.prod_log_retention_days

  tags = {
    App = each.value.name
    Env = "prod"
  }
}

resource "aws_cloudwatch_log_group" "staging" {
  for_each = var.apps

  name              = "/ecs/${each.value.name}-staging"
  retention_in_days = each.value.staging_log_retention_days

  tags = {
    App = each.value.name
    Env = "staging"
  }
}

# ── Task Definitions — Production ─────────────────────────────────────────────

resource "aws_ecs_task_definition" "prod" {
  for_each = var.apps

  family                   = "${each.value.name}-prod"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.prod_cpu
  memory                   = each.value.prod_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    merge({
      name      = each.value.name
      image     = "${local.ecr_repo_urls[each.key]}:latest"
      essential = true

      portMappings = each.value.enable_alb ? [
        {
          containerPort = each.value.container_port
          protocol      = "tcp"
        }
      ] : []

      secrets = []

      environment = [
        { name = "APP_NAME", value = each.value.name },
        { name = "ENVIRONMENT", value = "prod" },
        { name = "AWS_DEFAULT_REGION", value = var.aws_region },
        { name = "NODE_ENV", value = "production" },
        { name = "PORT", value = tostring(each.value.container_port) },
        { name = "ENV_S3_PATH", value = each.value.prod_env_s3_path }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.prod[each.key].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      # Active ECS Exec (debug shell)
      linuxParameters = {
        initProcessEnabled = true
      }
      }, each.value.runtime_entrypoint != "" ? {
      entryPoint = [each.value.runtime_entrypoint]
    } : {})
  ])

  # lifecycle ignore_changes supprimé sur container_definitions :
  # Terraform gère la définition de base (variables d'env, config conteneur).
  # Les pipelines deploy enregistrent de nouvelles révisions pour changer l'image tag
  # via describe-task-definition + register-task-definition — sans conflit avec Terraform.

  tags = {
    App = each.value.name
    Env = "prod"
  }
}

# ── Task Definitions — Staging ────────────────────────────────────────────────

resource "aws_ecs_task_definition" "staging" {
  for_each = var.apps

  family                   = "${each.value.name}-staging"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.staging_cpu
  memory                   = each.value.staging_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    merge({
      name      = "${each.value.name}-staging"
      image     = "${local.ecr_repo_urls[each.key]}:staging-latest"
      essential = true

      portMappings = each.value.enable_alb ? [
        {
          containerPort = each.value.container_port
          protocol      = "tcp"
        }
      ] : []

      secrets = []

      environment = [
        { name = "APP_NAME", value = each.value.name },
        { name = "ENVIRONMENT", value = "staging" },
        { name = "AWS_DEFAULT_REGION", value = var.aws_region },
        { name = "NODE_ENV", value = "staging" },
        { name = "PORT", value = tostring(each.value.container_port) },
        { name = "ENV_S3_PATH", value = each.value.staging_env_s3_path }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.staging[each.key].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      linuxParameters = {
        initProcessEnabled = true
      }
      }, each.value.runtime_entrypoint != "" ? {
      entryPoint = [each.value.runtime_entrypoint]
    } : {})
  ])

  # lifecycle ignore_changes supprimé — voir commentaire task def prod.

  tags = {
    App = each.value.name
    Env = "staging"
  }
}

# ── ECS Services — Production ─────────────────────────────────────────────────

resource "aws_ecs_service" "prod" {
  for_each = var.apps

  name                               = "${each.value.name}-prod-service"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.prod[each.key].arn
  desired_count                      = each.value.prod_desired_count
  launch_type                        = "FARGATE"
  enable_execute_command             = true
  health_check_grace_period_seconds  = 180
  deployment_minimum_healthy_percent = each.value.deployment_minimum_healthy_percent
  deployment_maximum_percent         = each.value.deployment_maximum_percent

  dynamic "deployment_circuit_breaker" {
    for_each = each.value.enable_deployment_circuit_breaker ? [true] : []

    content {
      enable   = true
      rollback = true
    }
  }

  network_configuration {
    subnets          = local.prod_subnets
    security_groups  = [aws_security_group.ecs_prod[each.key].id]
    assign_public_ip = true
  }

  dynamic "load_balancer" {
    for_each = each.value.enable_alb ? [true] : []

    content {
      target_group_arn = aws_lb_target_group.prod[each.key].arn
      container_name   = each.value.name
      container_port   = each.value.container_port
    }
  }

  depends_on = [aws_lb_listener_rule.prod]

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  tags = {
    App = each.value.name
    Env = "prod"
  }
}

# ── ECS Services — Staging ────────────────────────────────────────────────────

resource "aws_ecs_service" "staging" {
  for_each = var.apps

  name                               = "${each.value.name}-staging-service"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.staging[each.key].arn
  desired_count                      = each.value.staging_desired_count
  launch_type                        = "FARGATE"
  enable_execute_command             = true
  health_check_grace_period_seconds  = 180
  deployment_minimum_healthy_percent = each.value.deployment_minimum_healthy_percent
  deployment_maximum_percent         = each.value.deployment_maximum_percent

  dynamic "deployment_circuit_breaker" {
    for_each = each.value.enable_deployment_circuit_breaker ? [true] : []

    content {
      enable   = true
      rollback = true
    }
  }

  network_configuration {
    subnets          = local.staging_subnets
    security_groups  = [aws_security_group.ecs_staging[each.key].id]
    assign_public_ip = true
  }

  dynamic "load_balancer" {
    for_each = each.value.enable_alb ? [true] : []

    content {
      target_group_arn = aws_lb_target_group.staging[each.key].arn
      container_name   = "${each.value.name}-staging"
      container_port   = each.value.container_port
    }
  }

  depends_on = [aws_lb_listener_rule.staging]

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  tags = {
    App = each.value.name
    Env = "staging"
  }
}
