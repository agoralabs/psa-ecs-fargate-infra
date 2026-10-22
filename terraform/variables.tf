# ─────────────────────────────────────────────────────────────────────────────
# variables.tf — Variables globales et par application
# ─────────────────────────────────────────────────────────────────────────────

# ── AWS ───────────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "Région AWS"
  type        = string
  default     = "us-west-2"
}

variable "aws_profile" {
  description = "Profil AWS CLI à utiliser"
  type        = string
  default     = "psatechnologie"
}

variable "project_prefix" {
  description = "Préfixe global du projet (utilisé pour le nommage des ressources partagées)"
  type        = string
  default     = "psa"
}

# ── Réseau & ALB ──────────────────────────────────────────────────────────────

variable "alb_name" {
  description = "Nom de l'ALB existant partagé"
  type        = string
  default     = "psa-ypay-prod-lb"
}

variable "hosted_zone_name" {
  description = "Nom de la hosted zone Route 53"
  type        = string
  default     = "psatechnologie.com"
}

# ── CodeStar Connection (GitHub) ──────────────────────────────────────────────

variable "codestar_connection_arn" {
  description = "ARN de la CodeStar Connection GitHub (doit être créée et approuvée manuellement)"
  type        = string
}

# ── ECS Cluster partagé ───────────────────────────────────────────────────────

variable "ecs_cluster_name" {
  description = "Nom du cluster ECS Fargate partagé"
  type        = string
  default     = "psa-nestjs-cluster"
}

# ── S3 — bucket de configuration ─────────────────────────────────────────────

variable "env_config_s3_bucket" {
  description = "Nom du bucket S3 contenant les fichiers .env des applications (ex: makadi-app-config)"
  type        = string
  default     = "makadi-app-config"
}

# ─────────────────────────────────────────────────────────────────────────────
# Applications NestJS à déployer
# Chaque entrée du map correspond à une application indépendante.
# ─────────────────────────────────────────────────────────────────────────────

variable "apps" {
  description = "Map des applications NestJS à déployer"
  type = map(object({
    # Identifiant court de l'app (ex: "api-ecommerce")
    name = string

    # URL du dépôt GitHub (format : "owner/repo")
    github_repo_id = string

    # Branche de build (le pipeline build se déclenche sur cette branche)
    build_branch = string

    # Sous-domaines pour chaque environnement
    prod_domain    = string
    staging_domain = string

    # Hosted zone Route 53 pour cette application
    # Laisser à "" pour utiliser la hosted zone globale (var.hosted_zone_name)
    # Renseigner si l'app utilise un domaine différent (ex: "vtccontrol.com")
    hosted_zone_name = string

    # Port exposé par le conteneur
    container_port = number

    # CPU / Mémoire Fargate
    prod_cpu    = string
    prod_memory = string

    staging_cpu    = string
    staging_memory = string

    # Nombre de tâches désirées
    prod_desired_count    = number
    staging_desired_count = number

    # Health check path (NestJS: "/")
    health_check_path = string

    # Priorité des listener rules ALB (doit être unique par listener)
    prod_rule_priority    = number
    staging_rule_priority = number

    # Rétention des logs CloudWatch en jours
    # Valeurs acceptées : 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    prod_log_retention_days    = number
    staging_log_retention_days = number

    # Chemin S3 du fichier .env par environnement
    # Format : s3://bucket-name/path/to/.env
    # Utilisé par l'entrypoint du conteneur pour charger la configuration
    prod_env_s3_path    = string
    staging_env_s3_path = string

    # ── Pipelines optionnels ──────────────────────────────────────────────────
    # Mettre à false pour ne pas créer le pipeline correspondant
    enable_build_pipeline   = bool
    enable_release_pipeline = bool

    # Nom du script entrypoint dans le conteneur Docker
    # Exemples : "entrypoint.sh", "entrypoint-worker.sh"
    entrypoint_script = string

    # Clé ECR partagée (optionnel) — si renseignée, l'app réutilise le repo ECR
    # de l'app désignée au lieu d'en créer un nouveau.
    # Exemple : pour api-vtccontrol-worker, mettre "api-vtccontrol"
    # Laisser à "" pour créer un repo ECR dédié (comportement par défaut)
    ecr_repo_key = string

    # Type de machine CodeBuild pour le pipeline de build
    # BUILD_GENERAL1_SMALL  = 3 Go RAM  (défaut, moins cher)
    # BUILD_GENERAL1_MEDIUM = 7 Go RAM  (pour les projets gourmands : TSOA, tsc lourd, etc.)
    # BUILD_GENERAL1_LARGE  = 15 Go RAM (rare, gros monorepos)
    build_compute_type = string

    # ── Buckets S3 applicatifs (optionnel) ───────────────────────────────────
    # Mettre create_app_bucket = true pour créer un bucket prod ET un bucket staging.
    # Si les noms sont vides (""), les noms par défaut seront :
    #   prod    → "<name>-prod-data"
    #   staging → "<name>-staging-data"
    create_app_bucket       = bool
    app_bucket_name_prod    = string
    app_bucket_name_staging = string

    # ── Autoscaling ───────────────────────────────────────────────────────────
    # Nombre minimum et maximum de tâches ECS par environnement
    prod_autoscaling_min = number
    prod_autoscaling_max = number

    staging_autoscaling_min = number
    staging_autoscaling_max = number

    # Seuils de déclenchement du scaling (en %)
    # CPU : scale-out si > cible, scale-in si < cible pendant cooldown
    prod_autoscaling_cpu_target    = number
    prod_autoscaling_memory_target = number

    staging_autoscaling_cpu_target    = number
    staging_autoscaling_memory_target = number
  }))

  default = {}
}
