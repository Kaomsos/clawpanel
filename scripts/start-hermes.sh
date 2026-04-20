#!/usr/bin/env bash
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/root/.hermes}"
HERMES_GATEWAY_PORT="${HERMES_GATEWAY_PORT:-8642}"
HERMES_PROVIDER="${HERMES_PROVIDER:-openai}"
HERMES_MODEL="${HERMES_MODEL:-gpt-4o}"
HERMES_BASE_URL="${HERMES_BASE_URL:-}"
HERMES_API_KEY="${HERMES_API_KEY:-}"

mkdir -p "${HERMES_HOME}" /app/data
mkdir -p "${HERMES_HOME}"/{cron,sessions,logs,memories,skills,pairing,hooks,image_cache,audio_cache}

log() {
  printf '[hermes] %s\n' "$*"
}

if [ -z "${HERMES_API_KEY}" ]; then
  log "HERMES_API_KEY is empty"
  exit 1
fi

env_key="OPENAI_API_KEY"
base_key="OPENAI_BASE_URL"
if [ "${HERMES_PROVIDER}" = "anthropic" ]; then
  env_key="ANTHROPIC_API_KEY"
  base_key="ANTHROPIC_BASE_URL"
elif [ "${HERMES_PROVIDER}" = "openrouter" ]; then
  env_key="OPENROUTER_API_KEY"
  base_key="OPENAI_BASE_URL"
fi

cat > "${HERMES_HOME}/config.yaml" <<EOF
model:
  default: ${HERMES_MODEL}
$( [ -n "${HERMES_BASE_URL}" ] && printf "  base_url: %s\n" "${HERMES_BASE_URL}" )
api_server_port: ${HERMES_GATEWAY_PORT}
platform_toolsets:
  api_server:
    - hermes-api-server
terminal:
  backend: local
platforms:
  api_server:
    enabled: true
EOF

{
  echo "${env_key}=${HERMES_API_KEY}"
  echo "GATEWAY_ALLOW_ALL_USERS=true"
  echo "API_SERVER_KEY=clawpanel-local"
  if [ -n "${HERMES_BASE_URL}" ]; then
    echo "${base_key}=${HERMES_BASE_URL}"
  fi
} > "${HERMES_HOME}/.env"

log "starting Hermes Gateway on ${HERMES_GATEWAY_PORT}"
cd "${HERMES_HOME}"
set -a
. "${HERMES_HOME}/.env"
set +a
exec hermes gateway run > /app/data/hermes-gateway.log 2>&1
