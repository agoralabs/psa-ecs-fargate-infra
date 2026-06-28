#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# deploy.sh — Déclenche manuellement un pipeline de déploiement
#
# Usage :
#   ./scripts/deploy.sh <app-name> <environment> <image-tag>
#
# Exemples :
#   ./scripts/deploy.sh api-ecommerce staging staging-a1b2c3d4
#   ./scripts/deploy.sh api-ecommerce prod    staging-a1b2c3d4
#
# Le script démarre le CodePipeline correspondant et passe IMAGE_TAG
# comme variable de pipeline (V2).
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

APP_NAME="${1:-}"
ENVIRONMENT="${2:-}"
IMAGE_TAG="${3:-}"

AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_PROFILE="${AWS_PROFILE:-psatechnologie}"

# ── Validation ────────────────────────────────────────────────────────────────

if [[ -z "$APP_NAME" || -z "$ENVIRONMENT" || -z "$IMAGE_TAG" ]]; then
  echo "Usage: $0 <app-name> <environment> <image-tag>"
  echo "  app-name    : nom de l'application (ex: api-ecommerce)"
  echo "  environment : staging | prod"
  echo "  image-tag   : tag ECR à déployer (ex: staging-a1b2c3d4)"
  exit 1
fi

if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "prod" ]]; then
  echo "ERROR: environment doit être 'staging' ou 'prod'"
  exit 1
fi

PIPELINE_NAME="${APP_NAME}-${ENVIRONMENT}-pipeline"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Déploiement"
echo "  App         : $APP_NAME"
echo "  Environnement : $ENVIRONMENT"
echo "  Image Tag   : $IMAGE_TAG"
echo "  Pipeline    : $PIPELINE_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Vérifier que le pipeline existe
aws codepipeline get-pipeline \
  --name "$PIPELINE_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --output text --query 'pipeline.name' > /dev/null

# Démarrer le pipeline avec le paramètre IMAGE_TAG
EXECUTION_ID=$(aws codepipeline start-pipeline-execution \
  --name "$PIPELINE_NAME" \
  --variables "name=IMAGE_TAG,value=$IMAGE_TAG" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --output text --query 'pipelineExecutionId')

echo ""
echo "✅ Pipeline démarré — Execution ID : $EXECUTION_ID"
echo ""
echo "Suivi dans la console AWS :"
echo "  https://${AWS_REGION}.console.aws.amazon.com/codesuite/codepipeline/pipelines/${PIPELINE_NAME}/executions/${EXECUTION_ID}/timeline"
echo ""
echo "Ou via CLI :"
echo "  aws codepipeline get-pipeline-execution --pipeline-name $PIPELINE_NAME --pipeline-execution-id $EXECUTION_ID --profile $AWS_PROFILE --region $AWS_REGION"
