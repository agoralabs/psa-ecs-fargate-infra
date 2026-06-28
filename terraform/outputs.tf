# ─────────────────────────────────────────────────────────────────────────────
# outputs.tf — Sorties Terraform utiles
# ─────────────────────────────────────────────────────────────────────────────

output "ecs_cluster_name" {
  description = "Nom du cluster ECS partagé"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ARN du cluster ECS partagé"
  value       = aws_ecs_cluster.main.arn
}

output "alb_dns_name" {
  description = "DNS de l'ALB partagé"
  value       = data.aws_lb.shared.dns_name
}

output "ecr_repository_urls" {
  description = "URLs des repos ECR par application"
  value = {
    for k, v in aws_ecr_repository.app : k => v.repository_url
  }
}

output "prod_service_names" {
  description = "Noms des services ECS production"
  value = {
    for k, v in aws_ecs_service.prod : k => v.name
  }
}

output "staging_service_names" {
  description = "Noms des services ECS staging"
  value = {
    for k, v in aws_ecs_service.staging : k => v.name
  }
}

output "prod_urls" {
  description = "URLs de production par application"
  value = {
    for k, app in var.apps : k => "https://${app.prod_domain}"
  }
}

output "staging_urls" {
  description = "URLs de staging par application"
  value = {
    for k, app in var.apps : k => "https://${app.staging_domain}"
  }
}

output "build_pipeline_names" {
  description = "Noms des pipelines de build"
  value = {
    for k, v in aws_codepipeline.build : k => v.name
  }
}

output "staging_deploy_pipeline_names" {
  description = "Noms des pipelines de déploiement staging"
  value = {
    for k, v in aws_codepipeline.deploy_staging : k => v.name
  }
}

output "prod_deploy_pipeline_names" {
  description = "Noms des pipelines de déploiement prod"
  value = {
    for k, v in aws_codepipeline.deploy_prod : k => v.name
  }
}

output "release_pipeline_names" {
  description = "Noms des pipelines de release (tag ECR + tag Git)"
  value = {
    for k, v in aws_codepipeline.release : k => v.name
  }
}

output "ssm_parameter_paths" {
  description = "Chemins SSM des paramètres par app/env (à compléter avec les secrets)"
  value = {
    for k, app in var.apps : k => {
      prod    = "/${app.name}/prod/*"
      staging = "/${app.name}/staging/*"
    }
  }
}
