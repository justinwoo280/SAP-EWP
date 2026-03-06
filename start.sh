#!/bin/bash
set -e

UUID="${UUID:-d342d11e-d424-4583-b36e-524ab1f0afa4}"
PORT="${PORT:-8080}"
GRPC_SERVICE="${GRPC_SERVICE:-ProxyService}"

echo "[ewp] PORT=${PORT} GRPC_SERVICE=${GRPC_SERVICE}"

echo "[ewp] Generating self-signed TLS certificate..."
openssl req -x509 -newkey rsa:2048 \
  -keyout key.pem -out cert.pem \
  -days 3650 -nodes \
  -subj "/CN=localhost" \
  -addext "subjectAltName=IP:127.0.0.1,DNS:localhost" \
  2>/dev/null
echo "[ewp] TLS certificate generated"

cat > config.json << CFEOF
{
  "log": { "level": "info", "timestamp": true },
  "listener": {
    "port": ${PORT},
    "address": "0.0.0.0",
    "modes": ["grpc"],
    "grpc_service": "${GRPC_SERVICE}"
  },
  "protocol": {
    "type": "ewp",
    "uuid": "${UUID}",
    "enable_flow": true
  },
  "tls": {
    "enabled": true,
    "cert_file": "./cert.pem",
    "key_file": "./key.pem",
    "alpn": ["h2", "http/1.1"]
  },
  "advanced": {
    "enable_grpc_web": false,
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
