# Guide utilisateur — Pipelines & Surveillance ECS

**Audience** : développeurs et ops qui déploient et surveillent les applications NestJS sur AWS ECS Fargate.  
**Prérequis** : accès AWS Console ou AWS CLI configuré avec le profil `psatechnologie`.

---

## Vue d'ensemble des pipelines

Chaque application dispose de **4 pipelines** indépendants :

| Pipeline | Nom AWS | Déclenchement | Rôle |
|---|---|---|---|
| Build | `<app>-build-pipeline` | Automatique (commit sur `staging`) | Build Docker → push ECR |
| Deploy Staging | `<app>-staging-pipeline` | Manuel | Déploie un tag ECR sur ECS staging |
| Deploy Prod | `<app>-prod-pipeline` | Manuel | Déploie un tag ECR sur ECS prod |
| Release | `<app>-release-pipeline` | Manuel | Retag ECR : `staging-xxx` → `v1.x.y` |

**Exemple pour `api-ecommerce` :**
- `api-ecommerce-build-pipeline`
- `api-ecommerce-staging-pipeline`
- `api-ecommerce-prod-pipeline`
- `api-ecommerce-release-pipeline`

---

## Flux de déploiement standard

```
Développeur pousse sur la branche "staging"
              │
              ▼ automatique (5-10 min)
    ┌─────────────────────┐
    │   BUILD PIPELINE    │  → image staging-<sha> dans ECR
    └─────────────────────┘
              │
              ▼ décision manuelle
    ┌─────────────────────┐
    │  DEPLOY STAGING     │  → tester sur staging-<sha>
    └─────────────────────┘
              │
              ▼ validation OK
    ┌─────────────────────┐
    │  RELEASE PIPELINE   │  → créer v1.x.y depuis staging-<sha>
    └─────────────────────┘
              │
              ▼ décision manuelle
    ┌─────────────────────┐
    │   DEPLOY PROD       │  → déployer v1.x.y en production
    └─────────────────────┘
```

---

## 1. Pipeline BUILD — surveillance

### Où le trouver

AWS Console → **CodePipeline** → `api-ecommerce-build-pipeline`

### Ce qu'il fait

1. **Source** : détecte un commit sur la branche `staging` de GitHub
2. **Build** : construit l'image Docker et pousse deux tags dans ECR :
   - `staging-<sha>` (tag permanent, ex: `staging-a1b2c3d4`)
   - `staging-latest` (tag flottant, mis à jour à chaque build)

### Vérifier que le build s'est bien passé

**Dans la console CodePipeline :**

Aller sur le pipeline → la barre d'avancement affiche `Source` puis `Build`.  
Chaque étape doit être verte (`Succeeded`).

**Voir les logs de build :**

Cliquer sur l'étape **Build** → **Details** → **Link to execution details** → onglet **Logs**.

Les lignes importantes à repérer :
```
Logging into Amazon ECR...
Building image with tag: staging-a1b2c3d4
Successfully built ...
Successfully tagged ...
staging-a1b2c3d4: digest: sha256:...
staging-latest: digest: sha256:...
Build complete. Image: .../api-ecommerce:staging-a1b2c3d4
```

**Vérifier les images dans ECR :**

AWS Console → **ECR** → `api-ecommerce` → onglet **Images**  
Ou via CLI :
```bash
aws ecr describe-images \
  --repository-name api-ecommerce \
  --query "sort_by(imageDetails, &imagePushedAt) | reverse(@) | [:5].{Tag: to_string(imageTags[0]), Date: imagePushedAt}" \
  --output table \
  --profile psatechnologie --region us-west-2
```

### Causes fréquentes d'échec

| Symptôme | Cause probable |
|---|---|
| Étape Source en rouge | La CodeStar Connection GitHub n'est pas approuvée |
| `npm ci` échoue | Dépendances manquantes ou `package-lock.json` non committé |
| `docker build` échoue | Erreur de compilation TypeScript — voir les logs |
| `docker push` échoue | Permissions ECR insuffisantes sur le rôle CodeBuild |
| `prisma generate` échoue | `prisma/schema.prisma` absent ou invalide |

---

## 2. Pipeline DEPLOY STAGING — utilisation

### Quand l'utiliser

Après qu'un build a réussi et que vous voulez tester une version sur l'environnement staging.

### Déclencher le déploiement

**Via la console AWS :**

1. Aller sur **CodePipeline** → `api-ecommerce-staging-pipeline`
2. Cliquer **Release change** (bouton orange en haut à droite)
3. Dans le panneau **Pipeline variables**, renseigner `IMAGE_TAG` :
   - Valeur suggérée : `staging-a1b2c3d4` (le sha du build voulu)
   - Ou `staging-latest` pour la dernière image buildée
4. Cliquer **Release**

**Via CLI :**
```bash
./terraform/scripts/deploy.sh api-ecommerce staging staging-a1b2c3d4
```

### Ce qu'il fait en coulisses

1. Lit la task definition ECS actuelle (`api-ecommerce-staging`)
2. Remplace le tag de l'image par `IMAGE_TAG`
3. Enregistre une nouvelle révision de task definition
4. Lance `ecs update-service` — ECS démarre progressivement les nouvelles tâches

### Durée estimée

- Pipeline CodeBuild : 1-2 minutes
- Stabilisation ECS (nouvelles tâches healthy) : 2-5 minutes supplémentaires

---

## 3. Pipeline RELEASE — utilisation

### Quand l'utiliser

Après validation en staging, pour "figer" une version avant de la déployer en production.

### Déclencher une release

**Via la console AWS :**

1. Aller sur **CodePipeline** → `api-ecommerce-release-pipeline`
2. Cliquer **Release change**
3. Renseigner les deux variables :
   - `SOURCE_TAG` : tag source à promouvoir (ex: `staging-a1b2c3d4`) — défaut : `staging-latest`
   - `RELEASE_VERSION` : version cible (ex: `v1.2.0`) — défaut : `v1.0.0`
4. Cliquer **Release**

**Via CLI :**
```bash
# Depuis staging-latest
./terraform/scripts/release.sh api-ecommerce v1.2.0

# Depuis un tag précis
./terraform/scripts/release.sh api-ecommerce v1.2.0 staging-a1b2c3d4
```

### Ce qu'il fait

Retag l'image ECR `SOURCE_TAG` → `RELEASE_VERSION`. Aucun build, aucune modification de code.

### Vérifier la release

```bash
aws ecr describe-images \
  --repository-name api-ecommerce \
  --image-ids imageTag=v1.2.0 \
  --profile psatechnologie --region us-west-2
```

---

## 4. Pipeline DEPLOY PROD — utilisation

### Quand l'utiliser

Après avoir créé une release et vérifié qu'elle est stable en staging.

### Déclencher le déploiement

**Via la console AWS :**

1. Aller sur **CodePipeline** → `api-ecommerce-prod-pipeline`
2. Cliquer **Release change**
3. Renseigner `IMAGE_TAG` avec la version de release (ex: `v1.2.0`)
4. Cliquer **Release**

**Via CLI :**
```bash
./terraform/scripts/deploy.sh api-ecommerce prod v1.2.0
```

> ⚠️ Le déploiement en production est irréversible via le pipeline. Pour revenir en arrière,
> relancer le pipeline prod avec le tag de la version précédente.

---

## 5. Surveiller le déploiement ECS

### Comprendre le cycle de vie d'une tâche ECS

Quand un pipeline de déploiement se termine avec succès, ECS démarre un **rolling update** :

```
Nouvelle task definition enregistrée
              │
              ▼
ECS démarre une nouvelle tâche (PENDING → RUNNING)
              │
              ▼
Health check ALB : le conteneur répond sur /health (ou /)
              │
              ▼
Tâche déclarée HEALTHY → l'ancienne tâche est arrêtée (STOPPED)
              │
              ▼
Service stabilisé : runningCount == desiredCount
```

### Vérifier l'état du service dans la console

AWS Console → **ECS** → Cluster `psa-nestjs-cluster` → Services

| Service | Environnement |
|---|---|
| `api-ecommerce-prod-service` | Production |
| `api-ecommerce-staging-service` | Staging |

Dans la page du service, regarder :
- **Desired count** : nombre de tâches souhaitées
- **Running count** : doit être égal à Desired count une fois le déploiement terminé
- **Pending count** : doit retomber à 0 après quelques minutes

### Vérifier via CLI

```bash
aws ecs describe-services \
  --cluster psa-nestjs-cluster \
  --services api-ecommerce-prod-service \
  --profile psatechnologie --region us-west-2 \
  --query 'services[0].{
    Status: status,
    Desired: desiredCount,
    Running: runningCount,
    Pending: pendingCount,
    TaskDef: taskDefinition
  }'
```

### Voir les événements du service (dépannage)

Dans la console ECS → service → onglet **Events** : les événements sont listés
en ordre chronologique inverse. Un déploiement sain ressemble à :

```
service api-ecommerce-prod-service has reached a steady state.
service api-ecommerce-prod-service registered 1 targets under ...
(service api-ecommerce-prod-service) has started 1 tasks: (task abc123).
```

Un problème ressemble à :
```
(service api-ecommerce-prod-service) is unable to consistently start tasks successfully.
(service api-ecommerce-prod-service) task abc123 failed container health checks.
```

### Voir les tâches en cours

```bash
aws ecs list-tasks \
  --cluster psa-nestjs-cluster \
  --service-name api-ecommerce-prod-service \
  --profile psatechnologie --region us-west-2

# Détail d'une tâche
aws ecs describe-tasks \
  --cluster psa-nestjs-cluster \
  --tasks <TASK_ARN> \
  --profile psatechnologie --region us-west-2 \
  --query 'tasks[0].{
    Status: lastStatus,
    Health: healthStatus,
    Image: containers[0].image,
    StoppedReason: stoppedReason
  }'
```

---

## 6. Surveiller les logs applicatifs

### Via la console CloudWatch

AWS Console → **CloudWatch** → **Log groups**

| Log group | Environnement |
|---|---|
| `/ecs/api-ecommerce-prod` | Production |
| `/ecs/api-ecommerce-staging` | Staging |

Cliquer sur le log group → sélectionner le log stream le plus récent (nommé `ecs/api-ecommerce/<task-id>`).

### Via CLI (suivi en temps réel)

```bash
# Logs staging en temps réel
aws logs tail /ecs/api-ecommerce-staging \
  --follow \
  --profile psatechnologie --region us-west-2

# Logs prod en temps réel
aws logs tail /ecs/api-ecommerce-prod \
  --follow \
  --profile psatechnologie --region us-west-2

# Dernières 100 lignes
aws logs tail /ecs/api-ecommerce-prod \
  --since 30m \
  --profile psatechnologie --region us-west-2
```

### Lignes de log importantes au démarrage

Un démarrage sain affiche dans cet ordre :
```
Downloading .env from S3: s3://psa-nestjs-config/api-ecommerce/prod/.env
.env downloaded successfully
Loading environment variables from /usr/src/app/.env
[optionnel] Running Prisma migrations...     ← apps avec Prisma
Application is running on: http://[::1]:3000
```

Si vous voyez une de ces lignes, il y a un problème :
```
Warning: ENV_S3_PATH not set       → la variable ENV_S3_PATH n'est pas injectée
Error: Cannot connect to database  → DATABASE_URL manquante ou incorrecte dans le .env
Error: @prisma/client did not initialize  → image buildée sans prisma generate
```

---

## 7. Diagnostiquer un déploiement qui échoue

### Tâche qui ne démarre pas (reste PENDING)

Causes fréquentes :
- L'image ECR n'existe pas avec ce tag → vérifier dans ECR
- Pas assez de CPU/mémoire disponible dans le cluster → vérifier les ressources
- Le rôle IAM ne peut pas pull l'image → vérifier les permissions ECR

```bash
# Vérifier que le tag existe
aws ecr describe-images \
  --repository-name api-ecommerce \
  --image-ids imageTag=v1.2.0 \
  --profile psatechnologie --region us-west-2
```

### Tâche qui démarre et s'arrête immédiatement (STOPPED)

Regarder `stoppedReason` dans la description de la tâche et les logs CloudWatch.
Les causes les plus courantes :

| Symptôme dans les logs | Cause |
|---|---|
| `ENV_S3_PATH not set` + crash | Variable d'environnement non injectée dans la task definition |
| `NoSuchKey` ou `AccessDenied` sur S3 | Mauvais chemin S3 ou permissions insuffisantes |
| `Can't reach database` | `DATABASE_URL` absente ou incorrecte dans le `.env` S3 |
| `port already in use` | Impossible sur Fargate — probablement un crash immédiat |
| `exit code 1` sans log | Erreur dans l'entrypoint.sh avant le démarrage de Node |

### Health check ALB qui échoue

Si les tâches démarrent mais que le service n'arrive pas à se stabiliser, le health check
ALB échoue probablement. Vérifier :

1. Le path de health check (`/` ou `/health`) répond bien avec un HTTP 200-299
2. Le port du conteneur correspond au target group
3. Les security groups permettent le trafic depuis l'ALB

```bash
# Vérifier la santé des cibles dans le target group
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names api-ecommerce-prod-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text \
    --profile psatechnologie --region us-west-2) \
  --profile psatechnologie --region us-west-2 \
  --query 'TargetHealthDescriptions[].{
    Port: Target.Port,
    Health: TargetHealth.State,
    Reason: TargetHealth.Reason,
    Description: TargetHealth.Description
  }'
```

### Ouvrir un shell dans une tâche en cours (ECS Exec)

Pour déboguer interactivement une tâche qui tourne :

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

---

## 8. Rollback

### Revenir à la version précédente

Relancer le pipeline de déploiement avec l'ancien tag :

```bash
# Identifier la version précédente dans ECR
./terraform/scripts/list-images.sh api-ecommerce

# Redéployer l'ancienne version en prod
./terraform/scripts/deploy.sh api-ecommerce prod v1.1.0

# Ou en staging
./terraform/scripts/deploy.sh api-ecommerce staging staging-b2c3d4e5
```

### Rollback d'urgence via la console

1. AWS Console → **ECS** → Cluster `psa-nestjs-cluster` → Service `api-ecommerce-prod-service`
2. Onglet **Task definitions** → sélectionner la révision précédente
3. **Update service** → choisir la task definition précédente → **Update**

---

## 9. Opérations de maintenance

### Scaler à zéro (économie de coûts hors heures de bureau)

```bash
./terraform/scripts/scale.sh api-ecommerce staging 0
```

### Remettre en service

```bash
./terraform/scripts/scale.sh api-ecommerce staging 1
```

### Forcer un redémarrage sans changer l'image

```bash
aws ecs update-service \
  --cluster psa-nestjs-cluster \
  --service api-ecommerce-prod-service \
  --force-new-deployment \
  --profile psatechnologie --region us-west-2
```

Utile si le `.env` S3 a été mis à jour et que vous voulez que les tâches rechargent
la configuration sans changer le tag d'image.

---

## 10. Référence rapide — liens console AWS

> Remplacer `us-west-2` par votre région si différente.

| Ressource | URL |
|---|---|
| CodePipeline | https://us-west-2.console.aws.amazon.com/codesuite/codepipeline/pipelines |
| ECR | https://us-west-2.console.aws.amazon.com/ecr/repositories |
| ECS Cluster | https://us-west-2.console.aws.amazon.com/ecs/v2/clusters/psa-nestjs-cluster |
| CloudWatch Logs | https://us-west-2.console.aws.amazon.com/cloudwatch/home#logsV2:log-groups |
| ALB | https://us-west-2.console.aws.amazon.com/ec2/home#LoadBalancers |
