#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# add-ssm-secret.sh — Ajoute ou met à jour un secret SSM pour une app/env
#
# Usage :
#   ./scripts/add-ssm-secret.sh <app-name> <environment> <param-name> <value> [type]
#
# type : String | SecureString (défaut : SecureString)
#
# Exemples :
#   ./scripts/add-ssm-secret.sh api-ecommerce prod    DATABASE_URL "postgres://..."
#   ./scripts/add-ssm-secret.sh api-ecommerce staging JWT_SECRET   "mysecret"
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

APP_NAME="${1:-}"
ENVIRONMENT="${2:-}"
PARAM_NAME="${3:-}"
PARAM_VALUE="${4:-}"
PARAM_TYPE="${5:-SecureString}"

AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_PROFILE="${AWS_PROFILE:-psatechnologie}"

if [[ -z "$APP_NAME" || -z "$ENVIRONMENT" || -z "$PARAM_NAME" || -z "$PARAM_VALUE" ]]; then
  echo "Usage: $0 <app-name> <environment> <param-name> <value> [type]"
  echo "  type : String | SecureString (défaut: SecureString)"
  exit 1
fi

FULL_PATH="/${APP_NAME}/${ENVIRONMENT}/${PARAM_NAME}"

echo "Écriture du paramètre SSM : $FULL_PATH (type: $PARAM_TYPE)"

aws ssm put-parameter \
  --name "$FULL_PATH" \
  --value "$PARAM_VALUE" \
  --type "$PARAM_TYPE" \
  --overwrite \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE"

echo "✅ Paramètre $FULL_PATH créé/mis à jour"
echo ""
echo "Pour que l'application utilise ce secret, ajoutez dans ecs_tasks.tf :"
echo "  { name = \"$PARAM_NAME\", valueFrom = \"arn:aws:ssm:${AWS_REGION}:ACCOUNT_ID:parameter${FULL_PATH}\" }"
