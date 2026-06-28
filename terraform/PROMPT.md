# Infrastructure NestJS sur ECS Fargate — PSA Technologie

## Vue d'ensemble

Infrastructure Terraform pour déployer des applications NestJS sur AWS ECS Fargate.
Elle s'appuie sur l'ALB existant `psa-ypay-prod-lb` et utilise le routage par **Host header**
pour dispatcher le trafic vers chaque application et chaque environnement.

La structure est **multi-applications** : ajouter une nouvelle app NestJS revient à ajouter
une entrée dans `terraform.tfvars` sans modifier aucun fichier `.tf`.

---

## Architecture

```
GitHub (branche staging)
        │
        ▼ commit auto-détecté
┌─────────────────────────┐
│  Pipeline BUILD          │  <app>-build-pipeline
│  CodeBuild → ECR         │  push : staging-<sha> + staging-latest
└─────────────────────────┘
        │
        │  manuel (SOURCE_TAG + RELEASE_VERSION)
        ▼
┌─────────────────────────┐
│  Pipeline RELEASE        │  <app>-release-pipeline
│  retag ECR               │  staging-<sha> → v1.x.y
└─────────────────────────┘
        │
        │  manuel (IMAGE_TAG)
        ▼
┌─────────────────────────┐    ┌─────────────────────────┐
│  Pipeline DEPLOY staging │    │  Pipeline DEPLOY prod    │
│  <app>-staging-pipeline  │    │  <app>-prod-pipeline     │
│  CodeBuild update-service│    │  CodeBuild update-service│
└─────────────────────────┘    └─────────────────────────┘
        │                               │
        ▼                               ▼
  ECS Service staging             ECS Service prod
  (Host: api-ecommerce-staging     (Host: api-ecommerce
         .psatechnologie.com)              .psatechnologie.com)
        │                               │
        └───────────┬───────────────────┘
                    ▼
             ALB : psa-ypay-prod-lb
             Listener HTTPS 443
             Listener rules (Host header)
```

---

## Structure des fichiers

```
terraform/
├── main.tf               # Provider AWS, data sources (ALB, VPC, subnets, Route53)
├── variables.tf          # Toutes les variables, dont le map apps{}
├── terraform.tfvars      # Valeurs — à adapter (compte, connection ARN, apps)
├── cluster.tf            # Cluster ECS Fargate partagé
├── iam.tf                # Rôles IAM : ECS execution, ECS task, CodeBuild, CodePipeline
├── ecr.tf                # Repos ECR (un par app) + lifecycle policy
├── security_groups.tf    # SG ECS par app/env (ingress depuis ALB, descriptions ASCII)
├── dns_acm.tf            # Certificats ACM + enregistrements DNS Route 53
├── alb_rules.tf          # Target Groups + Listener Rules Host header
├── ecs_tasks.tf          # Task Definitions + Services ECS + Log groups
├── pipeline_build.tf     # Pipeline build (commit branche staging → ECR)
├── pipeline_deploy.tf    # Pipelines deploy staging + prod (manuel, IMAGE_TAG)
├── pipeline_release.tf   # Pipeline release (retag ECR : staging-x → v1.x.y)
├── outputs.tf            # Sorties : URLs, noms de services, pipelines
└── scripts/
    ├── deploy.sh          # Déclenche un pipeline de déploiement
    ├── release.sh         # Déclenche le pipeline de release (retag ECR)
    ├── list-images.sh     # Liste les images ECR disponibles
    ├── scale.sh           # Scale up/down un service ECS
    └── add-ssm-secret.sh  # Ajoute/met à jour un secret SSM
```

---

## Fichiers Terraform — Détail

### `main.tf`
- Configure le provider AWS (profile `psatechnologie`, région `us-west-2`)
- Charge les **data sources** partagées :
  - `data.aws_lb.shared` → ALB `psa-ypay-prod-lb`
  - `data.aws_lb_listener.https` → Listener 443 de l'ALB
  - `data.aws_lb_listener.http` → Listener 80
  - `data.aws_vpc.main` → VPC de l'ALB
  - `data.aws_subnets.public` → Subnets publics du VPC
  - `data.aws_route53_zone.main` → Zone `psatechnologie.com`

### `variables.tf`
- Variable `apps` : map d'objets décrivant chaque application NestJS
  - `name`, `github_repo_id`, `build_branch`
  - `prod_domain`, `staging_domain`
  - `container_port`, CPU/mémoire par env
  - `health_check_path`, `prod_rule_priority`, `staging_rule_priority`
  - `prod_log_retention_days`, `staging_log_retention_days`
  - `prod_env_s3_path`, `staging_env_s3_path`

### `terraform.tfvars`
- Valeurs concrètes : région, profil, ALB, hosted zone, CodeStar ARN
- Déclaration de l'application `api-ecommerce` (dépôt `agoralabs/demo-kaiac-api-nestjs`)
- Exemple commenté pour ajouter une deuxième application
- Priorités ALB à 200/210 (les priorités 1–17 sont déjà utilisées sur l'ALB existant)

### `cluster.tf`
- Crée le cluster ECS `psa-nestjs-cluster`
- Active Container Insights
- Capacity providers : FARGATE + FARGATE_SPOT

### `iam.tf`
- **ECS Task Execution Role** : pull ECR, lecture SSM
- **ECS Task Role** : permissions runtime (SSM, ECS Exec, CloudWatch)
- **CodeBuild Role** : ECR push/pull, ECS update-service, S3, CloudWatch, SSM
- **CodePipeline Role** : S3 artifacts, CodeBuild, CodeStar connection, ECS

### `ecr.tf`
- Un repo ECR par application (`for_each = var.apps`)
- `image_tag_mutability = "MUTABLE"` (requis pour le retag de la release)
- Lifecycle policy : conserver les 20 dernières images

### `security_groups.tf`
- Un SG ECS par application par environnement
- Ingress : port applicatif depuis le SG de l'ALB uniquement
- Fallback CIDR 0.0.0.0/0 si le SG de l'ALB n'est pas taggué
- Descriptions en ASCII pur (contrainte AWS sur les règles de SG)

### `dns_acm.tf`
- Certificats ACM (validation DNS) pour `prod_domain` et `staging_domain`
- Enregistrements Route 53 de validation
- Alias DNS `A` pointant vers l'ALB partagé

### `alb_rules.tf`
- **Target Groups** prod et staging (type `ip`, health check configurable)
- **Listener Rules** sur le listener HTTPS 443 :
  - Condition : `host_header` = domaine de l'app
  - Action : `forward` vers le target group correspondant
  - Priorités définies dans `terraform.tfvars` (doivent être uniques sur le listener)

### `ecs_tasks.tf`
- **CloudWatch Log Groups** `/ecs/<app>-prod` et `/ecs/<app>-staging`
  - Rétention configurable par app/env (`prod_log_retention_days`, `staging_log_retention_days`)
- **Task Definitions** prod et staging sans `ignore_changes` :
  - Terraform gère la définition de base ; les pipelines deploy enregistrent de nouvelles révisions pour changer l'image tag
  - Variables d'environnement injectées directement : `NODE_ENV`, `PORT`, `APP_NAME`, `ENVIRONMENT`, `AWS_DEFAULT_REGION`, `ENV_S3_PATH`
  - `ENV_S3_PATH` : chemin S3 du fichier `.env` téléchargé par l'entrypoint au démarrage
  - Bloc `secrets = []` vide — à compléter avec les vrais secrets via SSM
  - ECS Exec activé (`linuxParameters.initProcessEnabled`)
- **ECS Services** prod et staging :
  - Attachés aux target groups ALB
  - `launch_type = "FARGATE"`, subnets publics

### `pipeline_build.tf`
- S3 bucket pour les artefacts (versioning + chiffrement AES256)
- **CodeBuild `<app>-build`** :
  - Build Docker + push `staging-<sha>` et `staging-latest` dans ECR
  - `privileged_mode = true` (requis pour Docker)
- **CodePipeline `<app>-build-pipeline`** :
  - Source : GitHub via CodeStar Connection, `DetectChanges = true`
  - Branche : `build_branch` (défaut : `staging`)
  - Déclenchement **automatique** sur chaque commit

### `pipeline_deploy.tf`
- S3 bucket pour les artefacts de déploiement
- **CodeBuild `<app>-staging-deploy`** et **`<app>-prod-deploy`** :
  - Lit la task definition courante depuis ECS
  - Remplace le tag de l'image par `$IMAGE_TAG`
  - Enregistre une nouvelle révision de task definition
  - Met à jour le service ECS (`update-service`)
- **CodePipeline `<app>-staging-pipeline`** et **`<app>-prod-pipeline`** :
  - Type V2 avec variable `IMAGE_TAG`
  - `DetectChanges = false` → déclenchement **manuel uniquement**

### `pipeline_release.tf`
- **CodeBuild `<app>-tag-docker`** :
  - Pull l'image `SOURCE_TAG` depuis ECR
  - Retag en `RELEASE_VERSION`
  - Push le nouveau tag dans ECR
- **CodePipeline `<app>-release-pipeline`** :
  - Type V2 avec deux variables : `SOURCE_TAG` (défaut `staging-latest`) et `RELEASE_VERSION` (défaut `v1.0.0`)
  - `DetectChanges = false` → déclenchement **manuel uniquement**
  - Une seule étape : `TagDocker`

### `outputs.tf`
- URLs prod et staging par app
- Noms des services ECS, pipelines (build, staging, prod, release), repos ECR
- Chemins SSM à compléter avec les secrets applicatifs

---

## Scripts Shell

### `scripts/deploy.sh`
Déclenche manuellement un pipeline de déploiement.
```bash
./scripts/deploy.sh api-ecommerce staging staging-a1b2c3d4
./scripts/deploy.sh api-ecommerce prod    v1.2.0
```
- Appelle `aws codepipeline start-pipeline-execution` avec la variable `IMAGE_TAG`
- Affiche le lien de suivi dans la console AWS

### `scripts/release.sh`
Déclenche le pipeline de release (retag ECR).
```bash
./scripts/release.sh api-ecommerce v1.2.0
./scripts/release.sh api-ecommerce v1.2.0 staging-a1b2c3d4
```
- Passe `SOURCE_TAG` et `RELEASE_VERSION` au pipeline `<app>-release-pipeline`

### `scripts/list-images.sh`
Liste les images ECR disponibles pour une app, triées par date de push.
```bash
./scripts/list-images.sh api-ecommerce 20
```

### `scripts/scale.sh`
Scale up ou down un service ECS.
```bash
./scripts/scale.sh api-ecommerce staging 0  # scale to zero
./scripts/scale.sh api-ecommerce prod    2  # scale out
```

### `scripts/add-ssm-secret.sh`
Ajoute ou met à jour un paramètre SSM pour une app et un environnement.
```bash
./scripts/add-ssm-secret.sh api-ecommerce prod    DATABASE_URL "postgres://..."
./scripts/add-ssm-secret.sh api-ecommerce staging JWT_SECRET   "mysecret"
```
Les paramètres sont stockés sous `/<app>/<env>/<PARAM_NAME>`.
Pour les injecter dans le conteneur, ajouter une entrée dans le bloc `secrets` de `ecs_tasks.tf`.

---

## Workflow standard

### 1. Première installation

```bash
# 1. Renseigner terraform.tfvars
#    - codestar_connection_arn (créer dans AWS Console → Developer Tools → Connections)
#    - apps (ajuster les priorités ALB selon l'existant)

# 2. Initialiser Terraform
cd terraform
terraform init

# 3. Vérifier le plan
terraform plan

# 4. Appliquer
terraform apply
```

### 2. Cycle de développement complet

```
Commit sur branche staging
        │
        ▼ (automatique)
Pipeline BUILD → image staging-<sha> + staging-latest dans ECR

        │
        ▼ (manuel)
./scripts/deploy.sh api-ecommerce staging staging-<sha>
  → Test et validation en staging

        │
        ▼ (manuel — créer la release)
./scripts/release.sh api-ecommerce v1.2.0 staging-<sha>
  → Crée le tag ECR v1.2.0

        │
        ▼ (manuel — déployer en prod)
./scripts/deploy.sh api-ecommerce prod v1.2.0
```

### 3. Ajouter une nouvelle application

Dans `terraform.tfvars`, ajouter une entrée dans le map `apps` :

```hcl
"api-payments" = {
  name           = "api-payments"
  github_repo_id = "agoralabs/api-payments"
  build_branch   = "staging"
  prod_domain    = "api-payments.psatechnologie.com"
  staging_domain = "api-payments-staging.psatechnologie.com"
  container_port = 3000
  prod_cpu    = "512"   prod_memory = "1024"
  staging_cpu = "256"   staging_memory = "512"
  prod_desired_count    = 2
  staging_desired_count = 1
  health_check_path          = "/health"
  prod_rule_priority         = 220
  staging_rule_priority      = 230
  prod_log_retention_days    = 7
  staging_log_retention_days = 1
  prod_env_s3_path    = "s3://psa-nestjs-config/api-payments/prod/.env"
  staging_env_s3_path = "s3://psa-nestjs-config/api-payments/staging/.env"
}
```

Puis `terraform apply` — toutes les ressources sont créées automatiquement.

---

## Configuration ENV_S3_PATH

Chaque application charge sa configuration depuis un fichier `.env` stocké dans S3.
Le chemin est défini par `prod_env_s3_path` et `staging_env_s3_path` dans `terraform.tfvars`
et injecté comme variable d'environnement `ENV_S3_PATH` dans le conteneur ECS.

L'entrypoint (`docker/entrypoint.sh`) télécharge le fichier au démarrage :
```sh
aws s3 cp "$ENV_S3_PATH" /usr/src/app/.env
# puis exporte toutes les variables dans l'environnement du process Node
```

Pour uploader un `.env` :
```bash
aws s3 cp .env s3://psa-nestjs-config/api-ecommerce/prod/.env --profile psatechnologie
aws s3 cp .env s3://psa-nestjs-config/api-ecommerce/staging/.env --profile psatechnologie
```

---

## Prérequis

- Terraform >= 1.5
- AWS CLI configuré avec le profil `psatechnologie`
- **CodeStar Connection** créée et approuvée manuellement dans la console AWS
  - AWS Console → Developer Tools → Connections → Create connection (GitHub)
  - Copier l'ARN dans `terraform.tfvars`
- L'ALB `psa-ypay-prod-lb` doit exister avec un listener HTTPS 443
- La hosted zone `psatechnologie.com` doit exister dans Route 53
- Un bucket S3 doit exister pour héberger les fichiers `.env` (ex: `psa-nestjs-config`)

---

## Notes importantes

- Les priorités des listener rules ALB (`prod_rule_priority`, `staging_rule_priority`)
  doivent être **uniques** sur le listener. Les priorités 1–17 sont déjà utilisées sur
  `psa-ypay-prod-lb` — commencer à 200.
- Les `container_definitions` des task definitions n'ont plus de `ignore_changes` :
  Terraform gère la définition de base ; les pipelines deploy enregistrent de nouvelles
  révisions pour les mises à jour d'image sans conflit.
- `image_tag_mutability = "MUTABLE"` sur les repos ECR est nécessaire pour que le
  pipeline release puisse retagger une image existante.
- Pour les sous-réseaux privés (sans IP publique), adapter `assign_public_ip = false`
  et utiliser des subnets privés avec NAT Gateway dans `ecs_tasks.tf`.
