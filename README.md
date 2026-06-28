# psa-ecs-fargate-infra

Infrastructure Terraform pour déployer des applications **NestJS** sur **AWS ECS Fargate**.

Elle s'appuie sur l'ALB existant `psa-ypay-prod-lb` et route le trafic via le **Host header**
vers chaque application et chaque environnement. L'ajout d'une nouvelle app ne nécessite
aucune modification des fichiers `.tf` — seulement une entrée dans `terraform.tfvars`.

---

## Prérequis

| Outil | Version minimale |
|---|---|
| Terraform | >= 1.5 |
| AWS CLI | >= 2.x |

Profil AWS CLI configuré :
```bash
aws configure --profile psatechnologie
```

Ressources AWS existantes attendues :
- ALB `psa-ypay-prod-lb` avec listener HTTPS 443
- Hosted zone Route 53 `psatechnologie.com`
- Bucket S3 pour les fichiers `.env` (ex: `psa-nestjs-config`)

---

## Structure du dépôt

```
psa-ecs-fargate-infra/
├── .gitignore
├── README.md                    ← vous êtes ici
└── terraform/
    ├── main.tf                  # Provider, data sources (ALB, VPC, Route53)
    ├── variables.tf             # Variables dont le map apps{}
    ├── terraform.tfvars         # ⚠ À configurer avant terraform apply
    ├── cluster.tf               # Cluster ECS Fargate partagé
    ├── iam.tf                   # Rôles IAM (ECS, CodeBuild, CodePipeline)
    ├── ecr.tf                   # Repos ECR (un par app)
    ├── security_groups.tf       # SG ECS (ingress depuis ALB)
    ├── dns_acm.tf               # Certificats ACM + enregistrements DNS
    ├── alb_rules.tf             # Target Groups + listener rules Host header
    ├── ecs_tasks.tf             # Task definitions, services ECS, variables d'env
    ├── pipeline_build.tf        # Pipeline build auto (commit staging → ECR)
    ├── pipeline_deploy.tf       # Pipelines deploy staging + prod (manuels)
    ├── pipeline_release.tf      # Pipeline release (retag ECR staging → v1.x.y)
    ├── outputs.tf               # Sorties : URLs, noms de services, pipelines
    ├── PROMPT.md                # Documentation technique détaillée
    └── scripts/
        ├── deploy.sh            # Déclenche un déploiement
        ├── release.sh           # Déclenche une release (retag ECR)
        ├── list-images.sh       # Liste les images ECR
        ├── scale.sh             # Scale up/down un service ECS
        └── add-ssm-secret.sh    # Ajoute un secret dans SSM
```

---

## Installation initiale

### 1. Créer la CodeStar Connection GitHub

Dans la console AWS → **Developer Tools → Connections** :
1. Cliquer **Create connection**, choisir GitHub
2. Autoriser l'accès au(x) dépôt(s) souhaité(s)
3. Copier l'ARN de la connection

### 2. Configurer terraform.tfvars

```bash
cd terraform
```

Ouvrir `terraform.tfvars` et renseigner :

```hcl
codestar_connection_arn = "arn:aws:codeconnections:us-west-2:123456789012:connection/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

Vérifier les **priorités des listener rules** existantes sur l'ALB :

```bash
aws elbv2 describe-rules \
  --listener-arn $(aws elbv2 describe-listeners \
    --load-balancer-arn $(aws elbv2 describe-load-balancers \
      --names psa-ypay-prod-lb \
      --query 'LoadBalancers[0].LoadBalancerArn' --output text \
      --profile psatechnologie --region us-west-2) \
    --query 'Listeners[?Port==`443`].ListenerArn' --output text \
    --profile psatechnologie --region us-west-2) \
  --query 'Rules[].Priority' --output table \
  --profile psatechnologie --region us-west-2
```

Les priorités 1–17 étant déjà prises, `prod_rule_priority = 200` et `staging_rule_priority = 210` sont configurées par défaut.

### 3. Déployer l'infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

---

## Cycle de développement complet

```
1. Commit sur la branche "staging"
         │
         ▼  automatique
2. Pipeline build  →  staging-<sha> + staging-latest dans ECR

         │
         ▼  manuel
3. ./scripts/deploy.sh api-ecommerce staging staging-<sha>
   → Validation en staging

         │
         ▼  manuel
4. ./scripts/release.sh api-ecommerce v1.2.0 staging-<sha>
   → Crée le tag ECR v1.2.0

         │
         ▼  manuel
5. ./scripts/deploy.sh api-ecommerce prod v1.2.0
   → Déploiement en production
```

---

## Déploiement

### Déployer en staging

```bash
# Lister les images disponibles
./scripts/list-images.sh api-ecommerce

# Déployer un tag précis
./scripts/deploy.sh api-ecommerce staging staging-a1b2c3d4
```

### Créer une release

```bash
# Depuis staging-latest (défaut)
./scripts/release.sh api-ecommerce v1.2.0

# Depuis un tag précis
./scripts/release.sh api-ecommerce v1.2.0 staging-a1b2c3d4
```

Le pipeline retag l'image dans ECR. Aucun tag Git n'est créé.

### Déployer en production

```bash
./scripts/deploy.sh api-ecommerce prod v1.2.0
```

---

## Configuration du fichier .env

Chaque app/env charge sa configuration depuis un fichier `.env` stocké dans S3.
La variable `ENV_S3_PATH` est injectée dans le conteneur ECS et utilisée par
l'entrypoint au démarrage pour télécharger le fichier.

Uploader un `.env` :
```bash
aws s3 cp .env s3://psa-nestjs-config/api-ecommerce/prod/.env    --profile psatechnologie
aws s3 cp .env s3://psa-nestjs-config/api-ecommerce/staging/.env --profile psatechnologie
```

Le chemin S3 est défini dans `terraform.tfvars` :
```hcl
prod_env_s3_path    = "s3://psa-nestjs-config/api-ecommerce/prod/.env"
staging_env_s3_path = "s3://psa-nestjs-config/api-ecommerce/staging/.env"
```

---

## Ajouter une nouvelle application

Ouvrir `terraform/terraform.tfvars` et ajouter une entrée dans le map `apps` :

```hcl
"api-payments" = {
  name           = "api-payments"
  github_repo_id = "agoralabs/api-payments"
  build_branch   = "staging"

  prod_domain    = "api-payments.psatechnologie.com"
  staging_domain = "api-payments-staging.psatechnologie.com"

  container_port = 3000

  prod_cpu    = "512"
  prod_memory = "1024"
  staging_cpu    = "256"
  staging_memory = "512"

  prod_desired_count    = 2
  staging_desired_count = 1

  health_check_path = "/health"

  prod_rule_priority    = 220   # unique sur le listener ALB
  staging_rule_priority = 230

  prod_log_retention_days    = 7
  staging_log_retention_days = 1

  prod_env_s3_path    = "s3://psa-nestjs-config/api-payments/prod/.env"
  staging_env_s3_path = "s3://psa-nestjs-config/api-payments/staging/.env"
}
```

```bash
terraform plan
terraform apply
```

Toutes les ressources (ECR, ECS, ALB rules, DNS, ACM, pipelines) sont créées automatiquement.

---

## Gérer les secrets applicatifs

Les secrets sont stockés dans SSM Parameter Store sous `/<app>/<env>/<NOM>`.

```bash
# Ajouter un secret
./scripts/add-ssm-secret.sh api-ecommerce prod    DATABASE_URL "postgres://..."
./scripts/add-ssm-secret.sh api-ecommerce staging JWT_SECRET   "mon-secret"
```

Pour injecter le secret dans le conteneur, ajouter dans `ecs_tasks.tf` :

```hcl
secrets = [
  { name = "DATABASE_URL", valueFrom = "arn:aws:ssm:us-west-2:ACCOUNT_ID:parameter/api-ecommerce/prod/DATABASE_URL" }
]
```

Puis `terraform apply` + redéploiement.

---

## Opérations courantes

### Voir les URLs

```bash
cd terraform
terraform output prod_urls
terraform output staging_urls
```

### Tags d'images ECR

```bash
./scripts/list-images.sh api-ecommerce
./scripts/list-images.sh api-ecommerce 50
```

### Scaler un service

```bash
./scripts/scale.sh api-ecommerce staging 0   # éteindre (économie de coûts)
./scripts/scale.sh api-ecommerce staging 1   # rallumer
./scripts/scale.sh api-ecommerce prod    2   # scale out
```

### État des services ECS

```bash
aws ecs describe-services \
  --cluster psa-nestjs-cluster \
  --services api-ecommerce-prod-service api-ecommerce-staging-service \
  --profile psatechnologie --region us-west-2 \
  --query 'services[].{Name:serviceName, Running:runningCount, Desired:desiredCount, Status:status}'
```

### Shell dans un conteneur (ECS Exec)

```bash
TASK_ARN=$(aws ecs list-tasks \
  --cluster psa-nestjs-cluster \
  --service-name api-ecommerce-staging-service \
  --profile psatechnologie --region us-west-2 \
  --query 'taskArns[0]' --output text)

aws ecs execute-command \
  --cluster psa-nestjs-cluster \
  --task "$TASK_ARN" \
  --container api-ecommerce-staging \
  --interactive --command "/bin/sh" \
  --profile psatechnologie --region us-west-2
```

### Logs CloudWatch

```bash
aws logs tail /ecs/api-ecommerce-prod    --follow --profile psatechnologie --region us-west-2
aws logs tail /ecs/api-ecommerce-staging --follow --profile psatechnologie --region us-west-2
```

---

## Applications configurées

| Application | Dépôt GitHub | Prod | Staging |
|---|---|---|---|
| `api-ecommerce` | `agoralabs/demo-kaiac-api-nestjs` | `api-ecommerce.psatechnologie.com` | `api-ecommerce-staging.psatechnologie.com` |

---

## Ressources AWS créées

| Ressource | Nom(s) |
|---|---|
| Cluster ECS | `psa-nestjs-cluster` |
| ECR | `api-ecommerce` |
| ECS Services | `api-ecommerce-prod-service`, `api-ecommerce-staging-service` |
| Pipeline build | `api-ecommerce-build-pipeline` |
| Pipeline deploy staging | `api-ecommerce-staging-pipeline` |
| Pipeline deploy prod | `api-ecommerce-prod-pipeline` |
| Pipeline release | `api-ecommerce-release-pipeline` |
| Log groups | `/ecs/api-ecommerce-prod`, `/ecs/api-ecommerce-staging` |

---

## Documentation détaillée

Voir [`terraform/PROMPT.md`](terraform/PROMPT.md) pour la description complète
de chaque fichier Terraform et script Shell.
