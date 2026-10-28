#!/usr/bin/env bash
# Container entrypoint: repair OpenClaw state before the wrapper starts, then keep the gateway alive.
# Why: after a (re)deploy the gateway sometimes fails to start (state migration needed) and the
# wrapper never retries on its own (only an authenticated HTTP request does) -> bot silently down.
set -u
STATE_DIR="${OPENCLAW_STATE_DIR:-${CLAWDBOT_STATE_DIR:-/data/.openclaw}}"
export OPENCLAW_STATE_DIR="$STATE_DIR"
ENTRY="${OPENCLAW_ENTRY:-/openclaw/dist/entry.js}"

if [ -f "$STATE_DIR/openclaw.json" ]; then
  echo "[start] openclaw doctor --fix --non-interactive (state: $STATE_DIR)"
  timeout 240 node "$ENTRY" doctor --fix --non-interactive </dev/null >/tmp/doctor-boot.log 2>&1 \
    || echo "[start] doctor exited non-zero (continuing)"
fi

gateway_up() { pgrep -f '^openclaw-gateway' >/dev/null 2>&1; }
nudge() {
  local auth
  auth=$(printf 'admin:%s' "${SETUP_PASSWORD:-}" | base64 | tr -d '\n')
  curl -s -m 25 -o /dev/null -H "Authorization: Basic $auth" "http://127.0.0.1:${PORT:-8080}/" || true
}

(
  sleep 120
  while true; do
    if ! gateway_up; then
      echo "[keepalive] gateway not running -> nudging wrapper"
      nudge; sleep 45
      if ! gateway_up; then
        echo "[keepalive] still down -> doctor --fix, then nudge again"
        timeout 240 node "$ENTRY" doctor --fix </dev/null >/tmp/doctor-keepalive.log 2>&1 || true
        nudge
      fi
    fi
    sleep 60
  done
) &

exec node src/server.js
