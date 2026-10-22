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

Le build et la publication d'image restent ceux de l'application Ewatrack : l'ingestion n'a pas besoin d'un pipeline de build séparé. L'image commune doit cependant embarquer les trois scripts `entrypoint.sh`, `entrypoint-worker.sh` et `entrypoint-ingestion.sh`. La task ECS sélectionnera le script adapté au processus au runtime ; le pipeline de build ne doit pas produire une image différente pour l'ingestion.

Le champ actuel `entrypoint_script` est transmis au build Docker. Il ne permet donc pas à deux services partageant la même image de choisir des scripts différents au runtime. Il faut ajouter un paramètre distinct de démarrage au niveau de la task definition ECS, et conserver dans l'image les trois scripts exécutables. L'API garde `entrypoint.sh`, le worker utilise `entrypoint-worker.sh` et l'ingestion utilise `entrypoint-ingestion.sh`.

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

## Changements proposes par fichier

| Fichier / périmètre | Changement proposé |
|---|---|
| Dépôt source `psa-commits/api-ewatrack` | Ajouter `entrypoint-ingestion.sh` au dépôt, le rendre exécutable et le copier dans l'image Docker avec `entrypoint.sh` et `entrypoint-worker.sh`. Ajuster le Dockerfile pour embarquer les trois scripts dans une seule image, quel que soit le build argument par défaut. Le script ingestion doit charger la configuration comme les autres entrypoints puis lancer le processus d'ingestion attendu. Ce dépôt source n'est pas présent dans le workspace actuel : ces changements applicatifs restent à faire avant de déployer le nouveau service. |
| `terraform/terraform.tfvars` | Ajouter l'entrée `api-ewatrack-ingestion` avec le dépôt GitHub et le repo ECR partagés avec `api-ewatrack-worker`, les deux chemins `.env` existants, `desired_count = 1` dans les deux environnements et aucune création de bucket applicatif. Désactiver ses pipelines build/release dédiés ; garder les deux pipelines de déploiement. Fixer les limites d'autoscaling à 1 si le module les conserve. Ne pas utiliser `entrypoint_script` comme sélecteur runtime : ce champ est un paramètre de build. |
| `terraform/variables.tf` | Ajouter des attributs optionnels au type d'application, avec des valeurs par défaut qui préservent l'existant : exposition ALB désactivable, autoscaling désactivable, waiter de stabilisation activable et paramètres de déploiement ECS configurables. Ajouter un champ de démarrage runtime par environnement/conteneur pour sélectionner `entrypoint-worker.sh` ou `entrypoint-ingestion.sh`. Rendre optionnels les champs uniquement utilisés pour l'ALB (domaines, zone, health check et priorités) afin que l'ingestion n'ait pas besoin de valeurs factices. Terraform est déjà contraint à une version compatible avec les attributs optionnels d'objets. |
| `terraform/pipeline_build.tf` | Vérifier le rôle du build argument `ENTRYPOINT_SCRIPT`. Il peut continuer à choisir le démarrage par défaut de l'image, mais ne doit pas choisir quel fichier est embarqué : la même image doit toujours contenir les trois scripts. Adapter le buildspec seulement si le Dockerfile utilise actuellement cet argument pour n'en copier qu'un. |
| `terraform/ecs_tasks.tf` | Créer les task definitions/log groups prod et staging et les deux services ECS par les `for_each` existants. Configurer les services ingestion en `desired_count = 1`, `minimum_healthy_percent = 0` et `maximum_percent = 100`. Rendre le bloc `load_balancer` conditionnel et ne pas y attacher les services ingestion. Définir le démarrage runtime via `entryPoint` dans chaque task definition : `entrypoint-worker.sh` pour le worker et `entrypoint-ingestion.sh` pour l'ingestion (l'API conserve son démarrage actuel). Conserver les rôles ECS partagés, les logs CloudWatch, l'image/tag demandé et le chemin `ENV_S3_PATH` propre à l'environnement. |
| `terraform/autoscaling.tf` | Filtrer les ressources App Auto Scaling et les politiques CPU/mémoire pour les applications qui activent l'autoscaling. Ne pas créer de cible ni de politique pour l'ingestion ; sa capacité reste alors pilotée par `desired_count = 1`. Si le filtre n'est pas ajouté, imposer au minimum `min_capacity = max_capacity = 1`. |
| `terraform/security_groups.tf` | Ne pas créer de règle entrante depuis l'ALB pour l'ingestion. Conserver la sortie IPv4 existante, qui permet les connexions initiées par la tâche vers Redis et Flespi. |
| `terraform/alb_rules.tf` | Limiter target groups, règles de listener et certificats associés aux seules applications exposées en HTTP. Aucun target group ni routage ALB ne sera créé pour l'ingestion. |
| `terraform/dns_acm.tf` | Limiter certificats, validations DNS, recherches de zones et alias Route 53 aux applications exposées par l'ALB. Aucun domaine ni certificat n'est requis pour le consommateur MQTT. |
| `terraform/pipeline_deploy.tf` | Réutiliser les ressources génériques pour obtenir les CodeBuild projects et CodePipelines `api-ewatrack-ingestion-staging-pipeline` et `api-ewatrack-ingestion-prod-pipeline`. Ajouter un waiter ECS conditionnel et l'activer seulement pour ingestion afin de ne pas modifier les projets CodeBuild existants. Le rôle CodeBuild possède déjà `ecs:DescribeServices`, requis par le waiter. Le pipeline déploie le tag d'image choisi, sans construire une image distincte. |
| `terraform/outputs.tf` | Les sorties génériques des services et pipelines incluront l'application ingestion. Adapter les sorties d'URL et d'autoscaling pour ne pas annoncer d'URL ni de cible autoscaling pour ingestion. Exposer les IDs des SG ECS prod/staging pour la règle MemoryDB que le demandeur ajoutera. |
| SG de `vtc-memorydb` | Ajout de la règle d'entrée TCP 6379 pris en charge par le demandeur. Ce changement n'est pas inclus dans les modifications proposées au dépôt Terraform `psa-ecs-fargate-infra`. |

### Ressources attendues après application

Pour chacun des environnements, Terraform gère une task definition, un service ECS Fargate, un groupe de logs CloudWatch, un SG de tâche et un pipeline CodePipeline avec son projet CodeBuild et son bucket d'artefacts. Les deux services pointent vers le repo ECR Ewatrack, mais sont des services distincts afin de garder une capacité et une configuration propres à chaque environnement. L'image commune doit contenir les trois entrypoints et chaque service ECS sélectionne son script au runtime. La sortie `ewatrack_ingestion_security_group_ids` fournit les SG à autoriser dans MemoryDB.

Ne doivent pas être créés pour ces deux entrées : repo ECR supplémentaire, pipeline de build supplémentaire, pipeline de release, bucket de données applicatif, target group/règle ALB, certificat ACM, enregistrement DNS ou règle entrante ALB. La policy IAM ECS existante couvre déjà la lecture des fichiers `.env` S3, l'exécution des tâches, les logs et ECS Exec ; la policy CodeBuild couvre déjà les opérations ECS de déploiement et de description nécessaires.

### Déroulement de déploiement proposé

1. Le pipeline staging ou prod reçoit explicitement le tag ECR de l'image contenant les trois scripts. Il ne faut pas supposer que `staging-latest`/`latest` contient `entrypoint-ingestion.sh` simplement parce que le repo ECR est partagé.
2. CodeBuild récupère la task definition courante, remplace son image par le tag demandé, enregistre une nouvelle révision et appelle `aws ecs update-service`.
3. La configuration ECS autorise au plus une tâche active pour le service et permet de descendre temporairement à zéro tâche pendant le remplacement ; l'ancienne s'arrête avant le démarrage de la nouvelle.
4. CodeBuild attend `aws ecs wait services-stable` ; les logs et le test fonctionnel valident ensuite MQTT, Redis et l'affichage des positions.

Le déploiement « stop avant start » implique une interruption pendant le remplacement. Le circuit breaker ECS avec rollback est recommandé pour revenir à la dernière révision saine si la nouvelle task ne se stabilise pas ; il ne remplace pas la vérification de l'entrypoint ni le contrôle de l'unicité des identifiants Flespi.

## Vérifications avant déploiement

- Confirmer que l'image/tag déployé contient les trois scripts exécutables et que chaque task definition lance le script attendu : API, worker ou ingestion.
- Vérifier que les deux fichiers `.env` contiennent les paramètres Flespi et Redis attendus, sans les dupliquer dans la définition de task.
- Vérifier que la règle d'entrée TCP 6379 du SG MemoryDB a été ajoutée depuis les SG ingestion staging et prod (changement pris en charge par le demandeur).
- Vérifier DNS, route internet et connexion TCP/TLS vers `mqtt.flespi.io:8883` depuis une task dans chaque environnement.
- Contrôler dans ECS que `desiredCount = 1`, que le plafond reste à 1 et que le déploiement affiche au plus une tâche en cours d'exécution.
- Après déploiement, confirmer dans les logs la connexion MQTT, la réception de positions et leur écriture dans Redis, puis vérifier que la carte Ewatrack les affiche.