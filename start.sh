#!/bin/bash
set -e

UUID="${UUID:-d342d11e-d424-4583-b36e-524ab1f0afa4}"
PORT="${PORT:-8080}"
WS_PATH="${WS_PATH:-/}"

echo "[ewp] PORT=${PORT} WS_PATH=${WS_PATH}"

cat > config.json << CFEOF
{
  "log": { "level": "info", "timestamp": true },
  "listener": {
    "port": ${PORT},
    "address": "0.0.0.0",
    "modes": ["ws"],
    "ws_path": "${WS_PATH}"
  },
  "protocol": {
    "type": "ewp",
    "uuid": "${UUID}",
    "enable_flow": false
  },
  "advanced": {
    "padding_min": 100,
    "padding_max": 1000,
    "sse_headers": true
  }
}
CFEOF

echo "[ewp] config.json generated"

chmod +x ./ewp-server

if [ -n "${CLOUDFLARED_TOKEN}" ]; then
  echo "[cloudflare] CLOUDFLARED_TOKEN detected, setting up tunnel..."

  if [ -n "${CF_ACCOUNT_ID}" ] && [ -n "${CF_TUNNEL_ID}" ] && [ -n "${CF_API_TOKEN}" ]; then
    echo "[cloudflare] Configuring tunnel ingress via API (backend: http://localhost:${PORT})..."
    HTTP_CODE=$(curl -s -o /tmp/cf_api_resp.json -w "%{http_code}" \
      -X PUT "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${CF_TUNNEL_ID}/configurations" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"config\":{\"ingress\":[{\"service\":\"http://localhost:${PORT}\"},{\"service\":\"http_status:404\"}]}}")
    if [ "$HTTP_CODE" = "200" ]; then
      echo "[cloudflare] Tunnel ingress configured successfully -> http://localhost:${PORT}"
    else
      echo "[cloudflare] API call failed (HTTP ${HTTP_CODE})"
      cat /tmp/cf_api_resp.json || true
      echo "[cloudflare] Fallback: please manually set tunnel ingress to http://localhost:${PORT}"
    fi
  else
    echo "[cloudflare] CF_ACCOUNT_ID / CF_TUNNEL_ID / CF_API_TOKEN not set"
    echo "[cloudflare] !! Please configure tunnel ingress manually: http://localhost:${PORT} !!"
  fi

  chmod +x ./cloudflared
  ./cloudflared tunnel --no-autoupdate run --token "${CLOUDFLARED_TOKEN}" &
  CLOUDFLARED_PID=$!
  echo "[cloudflare] cloudflared started (PID=${CLOUDFLARED_PID})"
else
  echo "[ewp] No CLOUDFLARED_TOKEN, using SAP CF native routing on port ${PORT}"
fi

exec ./ewp-server -c config.json
