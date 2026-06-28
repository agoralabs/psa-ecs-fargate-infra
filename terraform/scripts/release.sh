#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# release.sh — Crée une release : retag ECR + tag Git
#
# Usage :
#   ./scripts/release.sh <app-name> <version> [source-tag]
#
# Exemples :
#   ./scripts/release.sh api-ecommerce v1.2.0
#   ./scripts/release.sh api-ecommerce v1.2.0 staging-a1b2c3d4
#
# source-tag défaut : staging-latest
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

APP_NAME="${1:-}"
RELEASE_VERSION="${2:-}"
SOURCE_TAG="${3:-staging-latest}"

AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_PROFILE="${AWS_PROFILE:-psatechnologie}"

if [[ -z "$APP_NAME" || -z "$RELEASE_VERSION" ]]; then
  echo "Usage: $0 <app-name> <version> [source-tag]"
  echo "  app-name    : nom de l'application (ex: api-ecommerce)"
  echo "  version     : version de release (ex: v1.2.0)"
  echo "  source-tag  : tag ECR source (défaut: staging-latest)"
  exit 1
fi

PIPELINE_NAME="${APP_NAME}-release-pipeline"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Release"
echo "  App             : $APP_NAME"
echo "  Source tag      : $SOURCE_TAG"
echo "  Release version : $RELEASE_VERSION"
echo "  Pipeline        : $PIPELINE_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Vérifier que le pipeline existe
aws codepipeline get-pipeline \
  --name "$PIPELINE_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --output text --query 'pipeline.name' > /dev/null

# Démarrer le pipeline avec les deux paramètres
EXECUTION_ID=$(aws codepipeline start-pipeline-execution \
  --name "$PIPELINE_NAME" \
  --variables "name=SOURCE_TAG,value=$SOURCE_TAG" "name=RELEASE_VERSION,value=$RELEASE_VERSION" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --output text --query 'pipelineExecutionId')

echo ""
echo "Release pipeline demarré — Execution ID : $EXECUTION_ID"
echo ""
echo "Suivi dans la console AWS :"
echo "  https://${AWS_REGION}.console.aws.amazon.com/codesuite/codepipeline/pipelines/${PIPELINE_NAME}/executions/${EXECUTION_ID}/timeline"
