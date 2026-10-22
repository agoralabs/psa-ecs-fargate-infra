# ─────────────────────────────────────────────────────────────────────────────
# autoscaling.tf — Application Auto Scaling ECS Fargate
#
# Stratégie :
#   - Scaling basé sur CPU (cible 70 %) et Mémoire (cible 80 %)
#   - Politique de scale-out rapide (cooldown 60s), scale-in conservateur (300s)
#   - Limites min/max configurables par app et par environnement
# ─────────────────────────────────────────────────────────────────────────────

# ── Scalable Targets — Production ────────────────────────────────────────────

resource "aws_appautoscaling_target" "prod" {
  for_each = var.apps

  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.prod[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"

  min_capacity = each.value.prod_autoscaling_min
  max_capacity = each.value.prod_autoscaling_max

  depends_on = [aws_ecs_service.prod]
}

# ── Scalable Targets — Staging ────────────────────────────────────────────────

resource "aws_appautoscaling_target" "staging" {
  for_each = var.apps

  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.staging[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"

  min_capacity = each.value.staging_autoscaling_min
  max_capacity = each.value.staging_autoscaling_max

  depends_on = [aws_ecs_service.staging]
}

# ── Politique CPU — Production ────────────────────────────────────────────────

resource "aws_appautoscaling_policy" "prod_cpu" {
  for_each = var.apps

  name               = "${each.value.name}-prod-cpu-scaling"
  service_namespace  = "ecs"
  resource_id        = aws_appautoscaling_target.prod[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.prod[each.key].scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.prod_autoscaling_cpu_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

# ── Politique Mémoire — Production ───────────────────────────────────────────

resource "aws_appautoscaling_policy" "prod_memory" {
  for_each = var.apps

  name               = "${each.value.name}-prod-memory-scaling"
  service_namespace  = "ecs"
  resource_id        = aws_appautoscaling_target.prod[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.prod[each.key].scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.prod_autoscaling_memory_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

# ── Politique CPU — Staging ───────────────────────────────────────────────────

resource "aws_appautoscaling_policy" "staging_cpu" {
  for_each = var.apps

  name               = "${each.value.name}-staging-cpu-scaling"
  service_namespace  = "ecs"
  resource_id        = aws_appautoscaling_target.staging[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.staging[each.key].scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.staging_autoscaling_cpu_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

# ── Politique Mémoire — Staging ───────────────────────────────────────────────

resource "aws_appautoscaling_policy" "staging_memory" {
  for_each = var.apps

  name               = "${each.value.name}-staging-memory-scaling"
  service_namespace  = "ecs"
  resource_id        = aws_appautoscaling_target.staging[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.staging[each.key].scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.staging_autoscaling_memory_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}
