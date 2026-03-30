#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

HOST=""
REMARK="gluetun-lan"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --remark)
      REMARK="${2:-}"
      shift 2
      ;;
    -h | --help)
      echo "Usage: $0 [--host <lan-ip>] [--remark <label>]" >&2
      echo "  Reads UUID from xray/config.json and XRAY_PORT from .env." >&2
      echo "  If --host is omitted, uses scripts/get-lan-ip.sh." >&2
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f .env ]]; then
  echo ".env not found. Create it first: cp .env.example .env" >&2
  exit 1
fi

XRAY_PORT="$(grep -E '^[[:space:]]*XRAY_PORT=' .env | head -1 | cut -d= -f2- | tr -d '\r' | tr -d ' ')"
[[ -n "${XRAY_PORT}" ]] || {
  echo "XRAY_PORT missing in .env" >&2
  exit 1
}

if [[ -z "${HOST}" ]]; then
  HOST="$("${SCRIPT_DIR}/get-lan-ip.sh")" || {
    echo "Could not detect LAN IP. Pass explicitly: $0 --host 192.168.1.10" >&2
    exit 1
  }
fi

python3 - "${HOST}" "${XRAY_PORT}" "${REMARK}" <<'PY'
import json, sys, urllib.parse

host, port_s, remark = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    port = int(port_s)
except ValueError:
    sys.exit("Invalid XRAY_PORT in .env")

with open("xray/config.json", encoding="utf-8") as f:
    cfg = json.load(f)

uuid = None
for ib in cfg.get("inbounds") or []:
    if ib.get("protocol") != "vless":
        continue
    st = ib.get("settings") or {}
    clients = st.get("clients") or []
    if clients and isinstance(clients[0], dict) and clients[0].get("id"):
        uuid = clients[0]["id"]
        break

if not uuid:
    sys.exit("No VLESS client id found in xray/config.json (run generate-secrets).")

frag = urllib.parse.quote(remark, safe="")
uri = f"vless://{uuid}@{host}:{port}?encryption=none&security=none&type=tcp&headerType=none#{frag}"
print(uri)
PY
