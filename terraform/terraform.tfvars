# ─────────────────────────────────────────────────────────────────────────────
# terraform.tfvars — Valeurs de configuration
# ─────────────────────────────────────────────────────────────────────────────

aws_region     = "us-west-2"
aws_profile    = "psatechnologie"
project_prefix = "psa"

alb_name         = "psa-ypay-prod-lb"
hosted_zone_name = "psatechnologie.com"
ecs_cluster_name = "psa-nestjs-cluster"

# Bucket S3 contenant les fichiers .env des applications
env_config_s3_bucket = "makadi-app-config"

# ARN de la CodeStar Connection GitHub
# À créer dans la console AWS → Developer Tools → Connections, puis approuver
codestar_connection_arn = "arn:aws:codeconnections:us-west-2:331816396577:connection/434fa1b9-b7ae-4bc4-9fb3-eb2bc55f279c"

# ─────────────────────────────────────────────────────────────────────────────
# Déclaration des applications
# Pour ajouter une nouvelle app, ajouter une entrée dans ce map.
# ─────────────────────────────────────────────────────────────────────────────

apps = {
  "api-ecommerce" = {
    name           = "api-ecommerce"
    github_repo_id = "psa-commits/backend_commerce2.0"
    build_branch   = "staging"

    prod_domain    = "api-ecommerce.psatechnologie.com"
    staging_domain = "api-ecommerce-staging.psatechnologie.com"

    # Zone globale psatechnologie.com
    hosted_zone_name = ""

    container_port = 3000

    prod_cpu    = "256"
    prod_memory = "512"

    staging_cpu    = "256"
    staging_memory = "512"

    prod_desired_count    = 1
    staging_desired_count = 1

    health_check_path = "/health"

    # Priorités ALB — doivent être uniques sur le listener
    # Priorités 1-17 déjà utilisées sur psa-ypay-prod-lb
    prod_rule_priority    = 200
    staging_rule_priority = 210

    # Rétention des logs CloudWatch
    prod_log_retention_days    = 1
    staging_log_retention_days = 1

    # Chemin S3 du fichier .env (utilisé par l'entrypoint pour charger la config)
    prod_env_s3_path    = "s3://makadi-app-config/api-ecommerce/prod/env.txt"
    staging_env_s3_path = "s3://makadi-app-config/api-ecommerce/staging/env.txt"

    # Pipelines optionnels (mettre false pour ne pas créer)
    enable_build_pipeline   = true
    enable_release_pipeline = true

    # Nom du script entrypoint (ex: entrypoint-worker.sh pour un worker)
    entrypoint_script = "entrypoint.sh"

    # Repo ECR partagé : "" = créer un repo dédié (défaut)
    ecr_repo_key = ""

    # Machine CodeBuild : SMALL (3Go/défaut) ou MEDIUM (7Go) si build gourmand
    build_compute_type = "BUILD_GENERAL1_SMALL"

    # ── Buckets S3 applicatifs (optionnel) ───────────────────────────────────
    # create_app_bucket = true  → crée un bucket prod ET un bucket staging
    # Noms par défaut si vides : "<app-name>-prod-data" / "<app-name>-staging-data"
    create_app_bucket       = false
    app_bucket_name_prod    = ""
    app_bucket_name_staging = ""

    # ── Autoscaling ───────────────────────────────────────────────────────────
    # Production : 1 à 4 tâches, scale sur CPU 70% et Mémoire 80%
    prod_autoscaling_min = 1
    prod_autoscaling_max = 4

    prod_autoscaling_cpu_target    = 70
    prod_autoscaling_memory_target = 80

    # Staging : 1 à 2 tâches, seuils plus permissifs pour économiser les coûts
    staging_autoscaling_min = 1
    staging_autoscaling_max = 2

    staging_autoscaling_cpu_target    = 80
    staging_autoscaling_memory_target = 85
  }

  "api-vtccontrol" = {
    name           = "api-vtccontrol"
    github_repo_id = "psa-commits/api-vtccontrol"
    build_branch   = "staging"

    prod_domain    = "api-vtccontrol.vtccontrol.com"
    staging_domain = "api-vtccontrol-staging.vtccontrol.com"

    # Zone différente de la zone globale
    hosted_zone_name = "vtccontrol.com"

    container_port = 3000

    prod_cpu    = "512"
    prod_memory = "1024"

    staging_cpu    = "512"
    staging_memory = "2048"

    prod_desired_count    = 1
    staging_desired_count = 1

    health_check_path = "/health"

    # Priorités ALB — doivent être uniques sur le listener
    # Priorités 1-17 déjà utilisées sur psa-ypay-prod-lb
    prod_rule_priority    = 300
    staging_rule_priority = 310

    # Rétention des logs CloudWatch
    prod_log_retention_days    = 1
    staging_log_retention_days = 1

    # Chemin S3 du fichier .env (utilisé par l'entrypoint pour charger la config)
    prod_env_s3_path    = "s3://makadi-app-config/api-vtccontrol/prod/env.txt"
    staging_env_s3_path = "s3://makadi-app-config/api-vtccontrol/staging/env.txt"

    # ── Pipelines optionnels ──────────────────────────────────────────────────
    enable_build_pipeline   = true
    enable_release_pipeline = true

    # Nom du script entrypoint dans le conteneur (ex: entrypoint-worker.sh)
    entrypoint_script = "entrypoint.sh"

    # Repo ECR partagé : "" = créer un repo dédié (défaut)
    ecr_repo_key = ""

    # LARGE (15Go) : package.json impose cross-env NODE_OPTIONS=8192 sur tsc
    # → pour repasser à MEDIUM, corriger le script "build" dans package.json
    build_compute_type = "BUILD_GENERAL1_LARGE"

    # ── Buckets S3 applicatifs (optionnel) ───────────────────────────────────
    create_app_bucket       = false
    app_bucket_name_prod    = ""
    app_bucket_name_staging = ""

    # ── Autoscaling ───────────────────────────────────────────────────────────
    # Production : 1 à 4 tâches, scale sur CPU 70% et Mémoire 80%
    prod_autoscaling_min = 1
    prod_autoscaling_max = 4

    prod_autoscaling_cpu_target    = 70
    prod_autoscaling_memory_target = 80

    # Staging : 1 à 2 tâches, seuils plus permissifs pour économiser les coûts
    staging_autoscaling_min = 1
    staging_autoscaling_max = 2

    staging_autoscaling_cpu_target    = 80
    staging_autoscaling_memory_target = 85
  }

  "api-vtccontrol-worker" = {
    name           = "api-vtccontrol-worker"
    github_repo_id = "psa-commits/api-vtccontrol"
    build_branch   = "staging"

    prod_domain    = "api-vtccontrol-worker.vtccontrol.com"
    staging_domain = "api-vtccontrol-worker-staging.vtccontrol.com"

    # Zone différente de la zone globale
    hosted_zone_name = "vtccontrol.com"

    container_port = 3000

    prod_cpu    = "256"
    prod_memory = "512"

    staging_cpu    = "256"
    staging_memory = "512"

    prod_desired_count    = 1
    staging_desired_count = 1

    health_check_path = "/health"

    # Priorités ALB — doivent être uniques sur le listener
    # Priorités 1-17 déjà utilisées sur psa-ypay-prod-lb
    prod_rule_priority    = 400
    staging_rule_priority = 410

    # Rétention des logs CloudWatch
    prod_log_retention_days    = 1
    staging_log_retention_days = 1

    # Chemin S3 du fichier .env (utilisé par l'entrypoint pour charger la config)
    prod_env_s3_path    = "s3://makadi-app-config/api-vtccontrol/prod/env.txt"
    staging_env_s3_path = "s3://makadi-app-config/api-vtccontrol/staging/env.txt"

    # ── Pipelines optionnels ──────────────────────────────────────────────────
    enable_build_pipeline   = false
    enable_release_pipeline = false

    # Nom du script entrypoint dans le conteneur (ex: entrypoint-worker.sh)
    entrypoint_script = "entrypoint-worker.sh"

    # Réutilise le repo ECR de api-vtccontrol (même image, entrypoint différent)
    ecr_repo_key = "api-vtccontrol"

    # LARGE (15Go) : même repo que api-vtccontrol, même contrainte mémoire
    build_compute_type = "BUILD_GENERAL1_LARGE"

    # ── Buckets S3 applicatifs (optionnel) ───────────────────────────────────
    create_app_bucket       = false
    app_bucket_name_prod    = ""
    app_bucket_name_staging = ""

    # ── Autoscaling ───────────────────────────────────────────────────────────
    prod_autoscaling_min = 1
    prod_autoscaling_max = 4

    prod_autoscaling_cpu_target    = 70
    prod_autoscaling_memory_target = 80

    staging_autoscaling_min = 1
    staging_autoscaling_max = 2

    staging_autoscaling_cpu_target    = 80
    staging_autoscaling_memory_target = 85
  }

  "api-ewatrack" = {
    name           = "api-ewatrack"
    github_repo_id = "psa-commits/api-ewatrack"
    build_branch   = "staging"

    prod_domain    = "api-ewatrack.ewatrack.com"
    staging_domain = "api-ewatrack-staging.ewatrack.com"

    # Zone différente de la zone globale
    hosted_zone_name = "ewatrack.com"

    container_port = 3000

    prod_cpu    = "256"
    prod_memory = "512"

    staging_cpu    = "256"
    staging_memory = "512"

    prod_desired_count    = 1
    staging_desired_count = 1

    health_check_path = "/health/live"

    # Priorités ALB — doivent être uniques sur le listener
    # Priorités 1-17 déjà utilisées sur psa-ypay-prod-lb
    prod_rule_priority    = 500
    staging_rule_priority = 510

    # Rétention des logs CloudWatch
    prod_log_retention_days    = 1
    staging_log_retention_days = 1

    # Chemin S3 du fichier .env (utilisé par l'entrypoint pour charger la config)
    prod_env_s3_path    = "s3://makadi-app-config/api-ewatrack/prod/env.txt"
    staging_env_s3_path = "s3://makadi-app-config/api-ewatrack/staging/env.txt"

    # ── Pipelines optionnels ──────────────────────────────────────────────────
    enable_build_pipeline   = true
    enable_release_pipeline = true

    # Nom du script entrypoint dans le conteneur (ex: entrypoint-worker.sh)
    entrypoint_script = "entrypoint.sh"

    # Repo ECR partagé : "" = créer un repo dédié (défaut)
    ecr_repo_key = ""

    # LARGE (15Go) : package.json impose cross-env NODE_OPTIONS=8192 sur tsc
    # → pour repasser à MEDIUM, corriger le script "build" dans package.json
    build_compute_type = "BUILD_GENERAL1_LARGE"

    # ── Buckets S3 applicatifs (optionnel) ───────────────────────────────────
    # create_app_bucket = true  → crée un bucket prod ET un bucket staging
    # Noms par défaut si vides : "<app-name>-prod-data" / "<app-name>-staging-data"
    create_app_bucket       = true
    app_bucket_name_prod    = ""
    app_bucket_name_staging = ""

    # ── Autoscaling ───────────────────────────────────────────────────────────
    # Production : 1 à 4 tâches, scale sur CPU 70% et Mémoire 80%
    prod_autoscaling_min = 1
    prod_autoscaling_max = 4

    prod_autoscaling_cpu_target    = 70
    prod_autoscaling_memory_target = 80

    # Staging : 1 à 2 tâches, seuils plus permissifs pour économiser les coûts
    staging_autoscaling_min = 1
    staging_autoscaling_max = 2

    staging_autoscaling_cpu_target    = 80
    staging_autoscaling_memory_target = 85
  }

  "api-psapay" = {
    name           = "api-psapay"
    github_repo_id = "psa-commits/backend_psapay"
    build_branch   = "staging"

    prod_domain    = "api-psapay.psatechnologie.com"
    staging_domain = "api-psapay-staging.psatechnologie.com"

    # Zone différente de la zone globale
    hosted_zone_name = ""

    container_port = 3000

    prod_cpu    = "256"
    prod_memory = "512"

    staging_cpu    = "256"
    staging_memory = "512"

    prod_desired_count    = 1
    staging_desired_count = 1

    health_check_path = "/health"

    # Priorités ALB — doivent être uniques sur le listener
    # Priorités 1-17 déjà utilisées sur psa-ypay-prod-lb
    prod_rule_priority    = 600
    staging_rule_priority = 610

    # Rétention des logs CloudWatch
    prod_log_retention_days    = 1
    staging_log_retention_days = 1

    # Chemin S3 du fichier .env (utilisé par l'entrypoint pour charger la config)
    prod_env_s3_path    = "s3://makadi-app-config/api-psapay/prod/env.txt"
    staging_env_s3_path = "s3://makadi-app-config/api-psapay/staging/env.txt"

    # ── Pipelines optionnels ──────────────────────────────────────────────────
    enable_build_pipeline   = true
    enable_release_pipeline = true

    # Nom du script entrypoint dans le conteneur (ex: entrypoint-worker.sh)
    entrypoint_script = "entrypoint.sh"

    # Repo ECR partagé : "" = créer un repo dédié (défaut)
    ecr_repo_key = ""

    # LARGE (15Go) : package.json impose cross-env NODE_OPTIONS=8192 sur tsc
    # → pour repasser à MEDIUM, corriger le script "build" dans package.json
    build_compute_type = "BUILD_GENERAL1_LARGE"

    # ── Buckets S3 applicatifs (optionnel) ───────────────────────────────────
    # create_app_bucket = true  → crée un bucket prod ET un bucket staging
    # Noms par défaut si vides : "<app-name>-prod-data" / "<app-name>-staging-data"
    create_app_bucket       = true
    app_bucket_name_prod    = ""
    app_bucket_name_staging = ""

    # ── Autoscaling ───────────────────────────────────────────────────────────
    # Production : 1 à 4 tâches, scale sur CPU 70% et Mémoire 80%
    prod_autoscaling_min = 1
    prod_autoscaling_max = 4

    prod_autoscaling_cpu_target    = 70
    prod_autoscaling_memory_target = 80

    # Staging : 1 à 2 tâches, seuils plus permissifs pour économiser les coûts
    staging_autoscaling_min = 1
    staging_autoscaling_max = 2

    staging_autoscaling_cpu_target    = 80
    staging_autoscaling_memory_target = 85
  }

  "api-psapay-worker" = {
    name           = "api-psapay-worker"
    github_repo_id = "psa-commits/backend_psapay"
    build_branch   = "staging"

    prod_domain    = "api-psapay-worker.psatechnologie.com"
    staging_domain = "api-psapay-worker-staging.psatechnologie.com"

    # Zone différente de la zone globale
    hosted_zone_name = ""

    container_port = 3000

    prod_cpu    = "256"
    prod_memory = "512"

    staging_cpu    = "256"
    staging_memory = "512"

    prod_desired_count    = 1
    staging_desired_count = 1

    health_check_path = "/health"

    # Priorités ALB — doivent être uniques sur le listener
    # Priorités 1-17 déjà utilisées sur psa-ypay-prod-lb
    prod_rule_priority    = 700
    staging_rule_priority = 710

    # Rétention des logs CloudWatch
    prod_log_retention_days    = 1
    staging_log_retention_days = 1

    # Chemin S3 du fichier .env (utilisé par l'entrypoint pour charger la config)
    prod_env_s3_path    = "s3://makadi-app-config/api-psapay/prod/env.txt"
    staging_env_s3_path = "s3://makadi-app-config/api-psapay/staging/env.txt"

    # ── Pipelines optionnels ──────────────────────────────────────────────────
    enable_build_pipeline   = false
    enable_release_pipeline = false

    # Nom du script entrypoint dans le conteneur (ex: entrypoint-worker.sh)
    entrypoint_script = "entrypoint-worker.sh"

    # Repo ECR partagé : "" = créer un repo dédié (défaut)
    ecr_repo_key = "api-psapay"

    # LARGE (15Go) : package.json impose cross-env NODE_OPTIONS=8192 sur tsc
    # → pour repasser à MEDIUM, corriger le script "build" dans package.json
    build_compute_type = "BUILD_GENERAL1_LARGE"

    # ── Buckets S3 applicatifs (optionnel) ───────────────────────────────────
    # create_app_bucket = true  → crée un bucket prod ET un bucket staging
    # Noms par défaut si vides : "<app-name>-prod-data" / "<app-name>-staging-data"
    create_app_bucket       = false
    app_bucket_name_prod    = "api-psapay-prod-data"
    app_bucket_name_staging = "api-psapay-staging-data"

    # ── Autoscaling ───────────────────────────────────────────────────────────
    # Production : 1 à 4 tâches, scale sur CPU 70% et Mémoire 80%
    prod_autoscaling_min = 1
    prod_autoscaling_max = 4

    prod_autoscaling_cpu_target    = 70
    prod_autoscaling_memory_target = 80

    # Staging : 1 à 2 tâches, seuils plus permissifs pour économiser les coûts
    staging_autoscaling_min = 1
    staging_autoscaling_max = 2

    staging_autoscaling_cpu_target    = 80
    staging_autoscaling_memory_target = 85
  }

  "api-ewatrack-worker" = {
    name           = "api-ewatrack-worker"
    github_repo_id = "psa-commits/api-ewatrack"
    build_branch   = "staging"

    prod_domain    = "api-ewatrack-worker.ewatrack.com"
    staging_domain = "api-ewatrack-worker-staging.ewatrack.com"

    # Zone différente de la zone globale
    hosted_zone_name = "ewatrack.com"

    container_port = 3000

    prod_cpu    = "256"
    prod_memory = "512"

    staging_cpu    = "256"
    staging_memory = "512"

    prod_desired_count    = 1
    staging_desired_count = 1

    health_check_path = "/health"

    # Priorités ALB — doivent être uniques sur le listener
    # Priorités 1-17 déjà utilisées sur psa-ypay-prod-lb
    prod_rule_priority    = 800
    staging_rule_priority = 810

    # Rétention des logs CloudWatch
    prod_log_retention_days    = 1
    staging_log_retention_days = 1

    # Chemin S3 du fichier .env (utilisé par l'entrypoint pour charger la config)
    prod_env_s3_path    = "s3://makadi-app-config/api-ewatrack/prod/env.txt"
    staging_env_s3_path = "s3://makadi-app-config/api-ewatrack/staging/env.txt"

    # ── Pipelines optionnels ──────────────────────────────────────────────────
    enable_build_pipeline   = false
    enable_release_pipeline = false

    # Nom du script entrypoint dans le conteneur (ex: entrypoint-worker.sh)
    entrypoint_script = "entrypoint-worker.sh"

    # Repo ECR partagé : "" = créer un repo dédié (défaut)
    ecr_repo_key = "api-ewatrack"

    # LARGE (15Go) : package.json impose cross-env NODE_OPTIONS=8192 sur tsc
    # → pour repasser à MEDIUM, corriger le script "build" dans package.json
    build_compute_type = "BUILD_GENERAL1_LARGE"

    # ── Buckets S3 applicatifs (optionnel) ───────────────────────────────────
    # create_app_bucket = true  → crée un bucket prod ET un bucket staging
    # Noms par défaut si vides : "<app-name>-prod-data" / "<app-name>-staging-data"
    create_app_bucket       = false
    app_bucket_name_prod    = ""
    app_bucket_name_staging = ""

    # ── Autoscaling ───────────────────────────────────────────────────────────
    # Production : 1 à 4 tâches, scale sur CPU 70% et Mémoire 80%
    prod_autoscaling_min = 1
    prod_autoscaling_max = 4

    prod_autoscaling_cpu_target    = 70
    prod_autoscaling_memory_target = 80

    # Staging : 1 à 2 tâches, seuils plus permissifs pour économiser les coûts
    staging_autoscaling_min = 1
    staging_autoscaling_max = 2

    staging_autoscaling_cpu_target    = 80
    staging_autoscaling_memory_target = 85
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
  #   # Zone Route53 : "" = zone globale (var.hosted_zone_name), sinon domaine custom
  #   hosted_zone_name = ""
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
  #
  #   # Chemins S3 des fichiers .env
  #   prod_env_s3_path    = "s3://makadi-app-config/api-payments/prod/env.txt"
  #   staging_env_s3_path = "s3://makadi-app-config/api-payments/staging/env.txt"
  #
  #   # Pipelines optionnels (mettre false pour ne pas créer)
  #   enable_build_pipeline   = true
  #   enable_release_pipeline = true
  #
  #   # Nom du script entrypoint (ex: entrypoint-worker.sh pour un worker)
  #   entrypoint_script = "entrypoint.sh"
  #
  #   # Repo ECR partagé : "" = repo dédié, "autre-app" = réutilise son repo ECR
  #   ecr_repo_key = ""
  #
  #   # Machine CodeBuild : SMALL (3Go/défaut) ou MEDIUM (7Go) si build gourmand
  #   build_compute_type = "BUILD_GENERAL1_SMALL"
  #
  #   # Bucket S3 applicatif (optionnel)
  #   # create_app_bucket = true  → crée un bucket prod ET un bucket staging
  #   # Noms par défaut : "<app-name>-prod-data" / "<app-name>-staging-data"
  #   # Noms personnalisés possibles via app_bucket_name_prod / app_bucket_name_staging
  #   create_app_bucket       = false
  #   app_bucket_name_prod    = ""
  #   app_bucket_name_staging = ""
  #
  #   # Autoscaling
  #   prod_autoscaling_min = 1
  #   prod_autoscaling_max = 4
  #   prod_autoscaling_cpu_target    = 70
  #   prod_autoscaling_memory_target = 80
  #
  #   staging_autoscaling_min = 1
  #   staging_autoscaling_max = 2
  #   staging_autoscaling_cpu_target    = 80
  #   staging_autoscaling_memory_target = 85
  # }
}
