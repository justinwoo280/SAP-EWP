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
    "enable_flow": true
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
  echo "[cloudflare] CLOUDFLARED_TOKEN detected"
  echo "[cloudflare] !! Set tunnel ingress origin to: https://localhost:${PORT} (No TLS Verify) !!"
  chmod +x ./cloudflared
  ./cloudflared tunnel --no-autoupdate run --token "${CLOUDFLARED_TOKEN}" &
  echo "[cloudflare] cloudflared started (PID=$!)"
else
  echo "[ewp] No CLOUDFLARED_TOKEN, using SAP CF native routing"
  echo "[ewp] !! Origin port: ${PORT} !!"
fi

exec ./ewp-server -c config.json
