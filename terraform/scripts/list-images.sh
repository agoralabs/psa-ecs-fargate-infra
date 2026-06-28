#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# list-images.sh — Liste les images ECR disponibles pour une application
#
# Usage :
#   ./scripts/list-images.sh <app-name> [max-results]
#
# Exemple :
#   ./scripts/list-images.sh api-ecommerce 20
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

APP_NAME="${1:-}"
MAX_RESULTS="${2:-20}"

AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_PROFILE="${AWS_PROFILE:-psatechnologie}"

if [[ -z "$APP_NAME" ]]; then
  echo "Usage: $0 <app-name> [max-results]"
  exit 1
fi

echo "Images ECR pour : $APP_NAME (les $MAX_RESULTS plus récentes)"
echo "────────────────────────────────────────────────────────────"

aws ecr describe-images \
  --repository-name "$APP_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query "sort_by(imageDetails, &imagePushedAt) | reverse(@) | [:${MAX_RESULTS}].{Tag: to_string(imageTags[0]), PushedAt: imagePushedAt, Size: imageSizeInBytes}" \
  --output table
