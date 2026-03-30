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

if ! command -v node >/dev/null 2>&1; then
  echo "node is required for print-vless-uri.sh (no usable python3 detected)." >&2
  exit 1
fi

node - "${HOST}" "${XRAY_PORT}" "${REMARK}" <<'NODE'
const fs = require('fs');

const host = process.argv[2];
const port = Number(process.argv[3]);
const remark = process.argv[4] ?? '';

if (!Number.isFinite(port)) {
  console.error('Invalid XRAY_PORT in .env');
  process.exit(1);
}

const cfg = JSON.parse(fs.readFileSync('xray/config.json', 'utf8'));

let uuid = null;
for (const ib of (cfg.inbounds || [])) {
  if (ib && ib.protocol === 'vless' && ib.settings && Array.isArray(ib.settings.clients)) {
    const c0 = ib.settings.clients[0];
    if (c0 && typeof c0 === 'object' && c0.id) {
      uuid = c0.id;
      break;
    }
  }
}

if (!uuid) {
  console.error('No VLESS client id found in xray/config.json (run generate-secrets).');
  process.exit(1);
}

const frag = encodeURIComponent(remark);
const uri = `vless://${uuid}@${host}:${port}?encryption=none&security=none&type=tcp&headerType=none#${frag}`;
console.log(uri);
NODE
