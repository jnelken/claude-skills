#!/usr/bin/env bash
set -euo pipefail

SERVICE_PATH="${1:?Usage: deploy.sh <service-path> <app/service> [health-url]}"
APP_SERVICE="${2:?Usage: deploy.sh <service-path> <app/service> [health-url]}"
HEALTH_URL="${3:-}"

if ! command -v koyeb >/dev/null 2>&1; then
  echo "koyeb CLI is required" >&2
  exit 1
fi

if [[ ! -d "${SERVICE_PATH}" ]]; then
  echo "Service path not found: ${SERVICE_PATH}" >&2
  exit 1
fi

echo "Deploying ${SERVICE_PATH} -> ${APP_SERVICE}"
koyeb deploy "${SERVICE_PATH}" "${APP_SERVICE}" --wait

if [[ -n "${HEALTH_URL}" ]]; then
  echo "Checking health: ${HEALTH_URL}"
  curl -i --fail --max-time 20 "${HEALTH_URL}"
fi

koyeb services get "${APP_SERVICE}"
echo "Deployment complete."
