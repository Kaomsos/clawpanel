#!/usr/bin/env bash
set -euo pipefail

PANEL_PORT="${PORT:-1420}"
OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
HERMES_GATEWAY_PORT="${HERMES_GATEWAY_PORT:-8642}"
AUTO_START_OPENCLAW_GATEWAY="${AUTO_START_OPENCLAW_GATEWAY:-1}"
AUTO_START_HERMES_GATEWAY="${AUTO_START_HERMES_GATEWAY:-0}"
HERMES_PROVIDER="${HERMES_PROVIDER:-openai}"
HERMES_MODEL="${HERMES_MODEL:-gpt-4o}"
HERMES_BASE_URL="${HERMES_BASE_URL:-}"
HERMES_API_KEY="${HERMES_API_KEY:-}"

OPENCLAW_HOME="${OPENCLAW_HOME:-/root/.openclaw}"
HERMES_HOME="${HERMES_HOME:-/root/.hermes}"

mkdir -p "${OPENCLAW_HOME}" "${HERMES_HOME}" /app/data
mkdir -p "${HERMES_HOME}"/{cron,sessions,logs,memories,skills,pairing,hooks,image_cache,audio_cache}

log() {
  printf '[fullstack] %s\n' "$*"
}

write_panel_config() {
  node --input-type=commonjs <<'EOF'
const fs = require('fs')
const path = require('path')

const openclawHome = process.env.OPENCLAW_HOME || '/root/.openclaw'
const panelConfigPath = path.join(openclawHome, 'clawpanel.json')
const hermesGatewayPort = process.env.HERMES_GATEWAY_PORT || '8642'
const hermesGatewayUrl = (process.env.HERMES_EXTERNAL_URL || `http://127.0.0.1:${hermesGatewayPort}`).replace(/\/+$/, '')

let cfg = {}
try {
  cfg = JSON.parse(fs.readFileSync(panelConfigPath, 'utf8'))
} catch {}
cfg.hermes = cfg.hermes || {}
cfg.hermes.gatewayUrl = hermesGatewayUrl
fs.mkdirSync(path.dirname(panelConfigPath), { recursive: true })
fs.writeFileSync(panelConfigPath, JSON.stringify(cfg, null, 2))
EOF
}

ensure_openclaw_config() {
  if [ ! -f "${OPENCLAW_HOME}/openclaw.json" ]; then
    log "initializing OpenClaw config"
    openclaw init >/tmp/openclaw-init.log 2>&1 || true
  fi

  node --input-type=commonjs <<'EOF'
const fs = require('fs')
const p = process.env.OPENCLAW_CONFIG_PATH || '/root/.openclaw/openclaw.json'
let cfg = {}
try {
  cfg = JSON.parse(fs.readFileSync(p, 'utf8'))
} catch {}
cfg.gateway = cfg.gateway || {}
cfg.gateway.port = Number(process.env.OPENCLAW_GATEWAY_PORT || '18789')
if (!cfg.gateway.mode) cfg.gateway.mode = 'local'
fs.mkdirSync(require('path').dirname(p), { recursive: true })
fs.writeFileSync(p, JSON.stringify(cfg, null, 2))
EOF
}

ensure_hermes_config() {
  if [ -z "${HERMES_API_KEY}" ]; then
    log "HERMES_API_KEY is empty; Hermes installed but gateway auto-start is skipped"
    return 1
  fi

  local env_key="OPENAI_API_KEY"
  local base_key="OPENAI_BASE_URL"
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
    echo "API_SERVER_HOST=0.0.0.0"
    if [ -n "${HERMES_BASE_URL}" ]; then
      echo "${base_key}=${HERMES_BASE_URL}"
    fi
  } > "${HERMES_HOME}/.env"

  return 0
}

OPENCLAW_PID=""
HERMES_PID=""
PANEL_PID=""

cleanup() {
  set +e
  [ -n "${PANEL_PID}" ] && kill "${PANEL_PID}" 2>/dev/null || true
  [ -n "${HERMES_PID}" ] && kill "${HERMES_PID}" 2>/dev/null || true
  [ -n "${OPENCLAW_PID}" ] && kill "${OPENCLAW_PID}" 2>/dev/null || true
  wait || true
}
trap cleanup EXIT INT TERM

write_panel_config
ensure_openclaw_config

if [ "${AUTO_START_OPENCLAW_GATEWAY}" = "1" ]; then
  log "starting OpenClaw Gateway on ${OPENCLAW_GATEWAY_PORT}"
  openclaw gateway run --bind lan --port "${OPENCLAW_GATEWAY_PORT}" > /app/data/openclaw-gateway.log 2>&1 &
  OPENCLAW_PID="$!"
else
  log "AUTO_START_OPENCLAW_GATEWAY=0; skip OpenClaw Gateway"
fi

if [ "${AUTO_START_HERMES_GATEWAY}" = "1" ]; then
  if ensure_hermes_config; then
    log "starting Hermes Gateway on ${HERMES_GATEWAY_PORT}"
    (
      cd "${HERMES_HOME}"
      export PATH="/root/.local/bin:${PATH}"
      set -a
      [ -f "${HERMES_HOME}/.env" ] && . "${HERMES_HOME}/.env"
      set +a
      hermes gateway run
    ) > /app/data/hermes-gateway.log 2>&1 &
    HERMES_PID="$!"
  fi
else
  log "AUTO_START_HERMES_GATEWAY=0; Hermes is preinstalled only"
fi

log "starting ClawPanel on ${PANEL_PORT}"
node /app/scripts/serve.js --host 0.0.0.0 --port "${PANEL_PORT}" &
PANEL_PID="$!"

wait -n "${PANEL_PID}" ${OPENCLAW_PID:+${OPENCLAW_PID}} ${HERMES_PID:+${HERMES_PID}}
