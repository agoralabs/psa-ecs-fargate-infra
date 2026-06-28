#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# scale.sh — Scale up/down un service ECS
#
# Usage :
#   ./scripts/scale.sh <app-name> <environment> <desired-count>
#
# Exemples :
#   ./scripts/scale.sh api-ecommerce staging 0   # scale to zero
#   ./scripts/scale.sh api-ecommerce staging 1   # scale up
#   ./scripts/scale.sh api-ecommerce prod    2   # scale out
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

APP_NAME="${1:-}"
ENVIRONMENT="${2:-}"
DESIRED_COUNT="${3:-}"

AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_PROFILE="${AWS_PROFILE:-psatechnologie}"
CLUSTER_NAME="${CLUSTER_NAME:-psa-nestjs-cluster}"

if [[ -z "$APP_NAME" || -z "$ENVIRONMENT" || -z "$DESIRED_COUNT" ]]; then
  echo "Usage: $0 <app-name> <environment> <desired-count>"
  exit 1
fi

SERVICE_NAME="${APP_NAME}-${ENVIRONMENT}-service"

echo "Scaling $SERVICE_NAME → $DESIRED_COUNT tâche(s)"

aws ecs update-service \
  --cluster "$CLUSTER_NAME" \
  --service "$SERVICE_NAME" \
  --desired-count "$DESIRED_COUNT" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --output text --query 'service.serviceName' > /dev/null

echo "✅ Service $SERVICE_NAME mis à $DESIRED_COUNT tâche(s)"
