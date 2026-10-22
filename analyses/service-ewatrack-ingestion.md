# Analyse - Service d'ingestion Ewatrack (staging et production)

## Synthese

Créer deux services ECS Fargate indépendants, un par environnement, pour connecter Ewatrack à Flespi et publier les positions dans Redis. Ils réutilisent le dépôt d'image ECR et les fichiers d'environnement déjà utilisés par le worker Ewatrack, mais ont leurs propres services ECS et pipelines de déploiement.

Noms proposés :

| Ressource | Staging | Production |
|---|---|---|
| Service ECS | `api-ewatrack-ingestion-staging-service` | `api-ewatrack-ingestion-prod-service` |
| Pipeline de déploiement | `api-ewatrack-ingestion-staging-pipeline` | `api-ewatrack-ingestion-prod-pipeline` |
| Famille de task definition | `api-ewatrack-ingestion-staging` | `api-ewatrack-ingestion-prod` |

## Reprise du modèle existant

Dans `terraform.tfvars`, `api-ewatrack-worker` partage déjà le dépôt ECR `api-ewatrack` (`ecr_repo_key = "api-ewatrack"`), le dépôt GitHub `psa-commits/api-ewatrack` et les fichiers d'environnement `api-ewatrack/{staging,prod}/env.txt`. L'entrée ingestion reprend ces références, avec un nom de service distinct et des ressources ECS/logs dédiées.

Le build et la publication d'image restent ceux de l'application Ewatrack : l'ingestion n'a pas besoin d'un pipeline de build séparé si elle exécute bien l'image publiée pour le worker. Les deux pipelines demandés sont les pipelines de déploiement, un pour staging et un pour prod, créés par le modèle existant indépendamment des options `enable_build_pipeline` et `enable_release_pipeline`.

Point à confirmer avant mise en service : `entrypoint_script` est transmis au build Docker, il ne modifie pas le démarrage d'une task à lui seul. Le tag d'image déployé doit donc effectivement démarrer le processus d'ingestion, et pas l'API HTTP ou un autre worker. Le partage de dépôt ECR ne garantit pas à lui seul que le contenu d'un tag donné est le bon.

## Une seule tâche, y compris pendant un déploiement

La valeur `desired_count = 1` ne suffit pas : le modèle courant permet l'autoscaling jusqu'à 4 tâches en prod et 2 en staging, et ECS utilise par défaut `maximum_percent = 200` et `minimum_healthy_percent = 100`, ce qui peut lancer la nouvelle tâche avant l'arrêt de l'ancienne.

Pour chaque service ingestion :

- fixer `desired_count` à 1 et borner l'autoscaling à `min = 1`, `max = 1` (ou ne pas créer de cible/politiques d'autoscaling pour ce type de service) ;
- configurer le déploiement ECS avec `minimum_healthy_percent = 0` et `maximum_percent = 100` : ECS arrête l'ancienne tâche avant d'en démarrer une nouvelle ;
- accepter une interruption pendant le remplacement : c'est le compromis nécessaire pour ne jamais avoir deux consommateurs connectés à Flespi ;
- faire attendre le pipeline jusqu'à la stabilisation du service (`aws ecs wait services-stable`) et activer le circuit breaker avec rollback si le nouveau déploiement échoue, si compatible avec le mode de déploiement retenu.

Ces limites s'appliquent à chaque environnement/service. Il faut aussi éviter un lancement manuel parallèle ou un second service pointant sur les mêmes identifiants Flespi si l'unicité attendue est globale à l'environnement.

## Réseau

| Flux | Règle nécessaire |
|---|---|
| Ingestion vers Redis `vtc-memorydb` | TCP sortant destination port 6379 ; le security group du cluster MemoryDB doit autoriser l'entrée TCP 6379 depuis le SG des tâches ingestion. |
| Ingestion vers Flespi `mqtt.flespi.io` | Résolution DNS et TCP sortant destination port 8883. Le SG ECS du dépôt autorise déjà la sortie IPv4 vers `0.0.0.0/0`, et les tâches ont une IP publique dans les subnets publics ; l'accès internet est donc prévu par le modèle actuel. |

La règle d'entrée Redis n'est pas visible dans ce dépôt et doit être vérifiée dans l'infrastructure qui possède `vtc-memorydb`. Une règle de SG AWS ne cible pas directement un nom DNS Flespi. Si la sortie générale est restreinte ultérieurement, il faudra prévoir un mécanisme d'egress adapté aux adresses Flespi plutôt qu'une règle basée sur le hostname.

## Ajustement Terraform nécessaire

Les ressources génériques de `ecs_tasks.tf` attachent chaque entrée de `var.apps` à un target group ALB HTTP, et `alb_rules.tf` crée aussi les règles listener, certificats et noms DNS associés. L'ingestion est un consommateur MQTT sortant, sans endpoint HTTP à publier : recopier simplement l'entrée du worker dans `apps` créerait ces ressources web et exigerait un health check HTTP qui ne correspond pas au service.

Recommandation : garder une configuration par environnement cohérente avec le worker pour ECS, l'image, les logs et le pipeline, mais rendre l'exposition ALB optionnelle ou isoler les services non HTTP. Pour ingestion, ne créer ni target group/règle ALB, ni certificat/DNS applicatif, ni ingress depuis l'ALB. Le SG peut conserver les sorties nécessaires et l'entrée Redis doit être explicitement autorisée par le SG MemoryDB.

## Vérifications avant déploiement

- Confirmer l'entrypoint réellement présent dans l'image/tag utilisé par le worker et l'ingestion.
- Vérifier que les deux fichiers `.env` contiennent les paramètres Flespi et Redis attendus, sans les dupliquer dans la définition de task.
- Vérifier la règle d'entrée TCP 6379 du SG MemoryDB depuis le SG ingestion pour les deux environnements.
- Vérifier DNS, route internet et connexion TCP/TLS vers `mqtt.flespi.io:8883` depuis une task dans chaque environnement.
- Contrôler dans ECS que `desiredCount = 1`, que le plafond reste à 1 et que le déploiement affiche au plus une tâche en cours d'exécution.
- Après déploiement, confirmer dans les logs la connexion MQTT, la réception de positions et leur écriture dans Redis, puis vérifier que la carte Ewatrack les affiche.