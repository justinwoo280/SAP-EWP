#!/bin/bash
set -euo pipefail

# -------------------------------------------------------------------
# Cloud Foundry start script for sing-box (EWP inbound, gRPC h2c).
#
# Architecture:
#   Client -- gRPC + TLS -->  SAP API Management gateway
#          -- gRPC h2c   -->  CF route ($CF_INSTANCE_INDEX...)
#          -- localhost  -->  sing-box on $PORT
#
# The gateway terminates TLS, so this container intentionally serves
# plaintext gRPC (h2c). Adding TLS here would require either pinning
# a self-signed cert in the gateway (operationally fragile) or paying
# for a second public cert (no security benefit).
# -------------------------------------------------------------------

if [[ -z "${UUID:-}" ]]; then
  echo "[ewp] FATAL: UUID env var is required" >&2
  echo "[ewp]        Run: cf set-env ewp-server UUID \$(uuidgen)" >&2
  exit 1
fi
if [[ -z "${PORT:-}" ]]; then
  echo "[ewp] FATAL: PORT not set (Cloud Foundry sets this at runtime)" >&2
  exit 1
fi

SINGBOX_TAG="${SINGBOX_TAG:-v1.12.19-mod.1}"
SINGBOX_REPO="${SINGBOX_REPO:-justinwoo280/sing-box}"
GRPC_SERVICE_NAME="${GRPC_SERVICE_NAME:-ewp}"

BIN_DIR="${HOME}/bin"
BIN="${BIN_DIR}/sing-box"
mkdir -p "${BIN_DIR}"

# -------------------------------------------------------------------
# Download sing-box on first boot. CF restages preserve $HOME/bin,
# so subsequent boots reuse the cached binary.
# -------------------------------------------------------------------
if [[ ! -x "${BIN}" ]]; then
  echo "[ewp] downloading sing-box ${SINGBOX_TAG} from ${SINGBOX_REPO}"
  ARCHIVE="sing-box-${SINGBOX_TAG#v}-linux-amd64.tar.gz"
  URL="https://github.com/${SINGBOX_REPO}/releases/download/${SINGBOX_TAG}/${ARCHIVE}"
  TMP="$(mktemp -d)"
  curl -fsSL --retry 3 --retry-delay 2 -o "${TMP}/sb.tar.gz" "${URL}"
  tar -xzf "${TMP}/sb.tar.gz" -C "${TMP}"
  # Release tar lays out as sing-box-<ver>-linux-amd64/sing-box
  find "${TMP}" -name sing-box -type f -executable -exec mv {} "${BIN}" \;
  rm -rf "${TMP}"
  chmod +x "${BIN}"
fi

echo "[ewp] sing-box version: $(${BIN} version | head -1)"
echo "[ewp] PORT=${PORT}  GRPC_SERVICE_NAME=${GRPC_SERVICE_NAME}"

# -------------------------------------------------------------------
# Generate sing-box config.
#
# Notes on choices:
#   - listen 0.0.0.0:$PORT     CF assigns $PORT, must bind there
#   - tls.enabled = false      gateway terminates TLS upstream
#   - transport.type = grpc    matches gateway's gRPC route
#   - direct outbound only     this is a plain forwarder; no DNS,
#                              no router rules, the gateway already
#                              handles ingress policy
# -------------------------------------------------------------------
cat > config.json <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "ewp",
      "tag": "ewp-in",
      "listen": "0.0.0.0",
      "listen_port": ${PORT},
      "users": [
        {
          "name": "default",
          "uuid": "${UUID}"
        }
      ],
      "transport": {
        "type": "grpc",
        "service_name": "${GRPC_SERVICE_NAME}"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

echo "[ewp] config.json generated"
exec "${BIN}" run -c config.json
