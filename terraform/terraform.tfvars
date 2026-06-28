# ─────────────────────────────────────────────────────────────────────────────
# terraform.tfvars — Valeurs de configuration
# ─────────────────────────────────────────────────────────────────────────────

aws_region     = "us-west-2"
aws_profile    = "psatechnologie"
project_prefix = "psa"

alb_name         = "psa-ypay-prod-lb"
hosted_zone_name = "psatechnologie.com"
ecs_cluster_name = "psa-nestjs-cluster"

# ARN de la CodeStar Connection GitHub
# À créer dans la console AWS → Developer Tools → Connections, puis approuver
codestar_connection_arn = "arn:aws:codeconnections:us-west-2:331816396577:connection/248a1d10-52fa-4af5-8502-558af6bd395a"

# ─────────────────────────────────────────────────────────────────────────────
# Déclaration des applications
# Pour ajouter une nouvelle app, ajouter une entrée dans ce map.
# ─────────────────────────────────────────────────────────────────────────────

apps = {
  "api-ecommerce" = {
    name           = "api-ecommerce"
    github_repo_id = "agoralabs/demo-kaiac-api-nestjs"
    build_branch   = "staging"

    prod_domain    = "api-ecommerce.psatechnologie.com"
    staging_domain = "api-ecommerce-staging.psatechnologie.com"

    container_port = 3000

    prod_cpu    = "256"
    prod_memory = "512"

    staging_cpu    = "256"
    staging_memory = "512"

    prod_desired_count    = 1
    staging_desired_count = 1

    health_check_path = "/"

    # Priorités ALB — doivent être uniques sur le listener
    # Priorités 1-17 déjà utilisées sur psa-ypay-prod-lb
    prod_rule_priority    = 200
    staging_rule_priority = 210

    # Rétention des logs CloudWatch
    prod_log_retention_days    = 1
    staging_log_retention_days = 1

    # Chemin S3 du fichier .env (utilisé par l'entrypoint pour charger la config)
    prod_env_s3_path    = "s3://makadi-app-config/api-ecommerce/prod/.env"
    staging_env_s3_path = "s3://makadi-app-config/api-ecommerce/staging/.env"
  }

  # ── Exemple d'une deuxième application ─────────────────────────────────────
  # "api-payments" = {
  #   name           = "api-payments"
  #   github_repo_id = "agoralabs/api-payments"
  #   build_branch   = "staging"
  #
  #   prod_domain    = "api-payments.psatechnologie.com"
  #   staging_domain = "api-payments-staging.psatechnologie.com"
  #
  #   container_port = 3000
  #
  #   prod_cpu    = "512"
  #   prod_memory = "1024"
  #
  #   staging_cpu    = "256"
  #   staging_memory = "512"
  #
  #   prod_desired_count    = 2
  #   staging_desired_count = 1
  #
  #   health_check_path = "/health"
  #
  #   prod_rule_priority    = 120
  #   staging_rule_priority = 130
  #
  #   # Rétention des logs CloudWatch (en jours)
  #   prod_log_retention_days    = 7
  #   staging_log_retention_days = 1
  # }
}
