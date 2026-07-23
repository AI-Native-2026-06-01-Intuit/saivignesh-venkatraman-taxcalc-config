#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"
SERVICE="${2:-}"
IMAGE_TAG="${3:-}"
CONFIG_REPO_ROOT="${4:-$(cd "$(dirname "$0")/.." && pwd)}"

ALLOWED_ENVS=(dev staging prod)
ALLOWED_SERVICES=(taxcalc-api taxcalc-agent-svc taxcalc-mcp-server taxcalc-web)

declare -A IMAGE_NAMES=(
  [taxcalc-api]=uptimecrew/taxcalc-api
  [taxcalc-agent-svc]=uptimecrew/taxcalc-agent-svc
  [taxcalc-mcp-server]=uptimecrew/taxcalc-mcp-server
  [taxcalc-web]=uptimecrew/taxcalc-web
)

if [[ ! " ${ALLOWED_ENVS[*]} " =~ " ${ENVIRONMENT} " ]]; then
  echo "unknown environment: ${ENVIRONMENT}" >&2
  exit 2
fi
if [[ ! " ${ALLOWED_SERVICES[*]} " =~ " ${SERVICE} " ]]; then
  echo "unknown service: ${SERVICE}" >&2
  exit 2
fi
if [[ -z "$IMAGE_TAG" || "$IMAGE_TAG" == "latest" ]]; then
  echo "image_tag must be a non-empty immutable tag" >&2
  exit 2
fi

OVERLAY="${CONFIG_REPO_ROOT}/overlays/${ENVIRONMENT}"
IMAGE_BASE="${IMAGE_NAMES[$SERVICE]}"
(
  cd "$OVERLAY"
  kustomize edit set image "${IMAGE_BASE}=${IMAGE_BASE}:${IMAGE_TAG}"
  kustomize build . >/tmp/kustomize-rendered.yaml
)

if [[ "$SERVICE" == "taxcalc-agent-svc" ]]; then
  PATCH="${OVERLAY}/patch-agent-version-label.yaml"
  if [[ -f "$PATCH" ]]; then
    if sed --version >/dev/null 2>&1; then
      sed -i "s/app.kubernetes.io\\/version: .*/app.kubernetes.io\\/version: ${IMAGE_TAG}/" "$PATCH"
    else
      sed -i '' "s/app.kubernetes.io\\/version: .*/app.kubernetes.io\\/version: ${IMAGE_TAG}/" "$PATCH"
    fi
  fi
fi

echo "updated ${SERVICE} in overlays/${ENVIRONMENT} to tag ${IMAGE_TAG}"
