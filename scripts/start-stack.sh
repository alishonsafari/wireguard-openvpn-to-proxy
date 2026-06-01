#!/usr/bin/env bash
set -euo pipefail

PROFILE_PATH=""
HOST=""
REMARK="gluetun-lan"
ENV_PATH="./.env"
VPN_WAIT_SECS=120

usage() {
  echo "Usage: $0 --profile-path <profiles/file.conf|.ovpn> [--host <lan-ip>] [--remark <label>] [--env-path <path>]" >&2
  echo "  Applies VPN profile, starts Docker (gluetun + xray), waits for VPN, prints two VLESS URIs (LAN + 127.0.0.1)." >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile-path | -profile-path)
      [[ $# -ge 2 ]] || usage
      PROFILE_PATH="${2}"
      shift 2
      ;;
    --host | -host)
      [[ $# -ge 2 ]] || usage
      HOST="${2}"
      shift 2
      ;;
    --remark | -remark)
      [[ $# -ge 2 ]] || usage
      REMARK="${2}"
      shift 2
      ;;
    --env-path)
      [[ $# -ge 2 ]] || usage
      ENV_PATH="${2}"
      shift 2
      ;;
    --timeout)
      [[ $# -ge 2 ]] || usage
      VPN_WAIT_SECS="${2}"
      shift 2
      ;;
    -h | --help)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

[[ -n "${PROFILE_PATH}" ]] || usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ "${PROFILE_PATH}" != /* ]]; then
  PROFILE_PATH="${REPO_ROOT}/${PROFILE_PATH#./}"
fi
if [[ "${ENV_PATH}" != /* ]]; then
  ENV_PATH="${REPO_ROOT}/${ENV_PATH#./}"
fi

log() { printf '%s\n' "$*"; }
ok() { log "[OK] $*"; }
info() { log "[..] $*"; }
fail() { log "[ERROR] $*"; exit 1; }

_color_enabled() {
  [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]
}

# Print a VLESS URI in a bordered, colored block (TTY only).
print_vless_box() {
  local title="$1"
  local uri="$2"
  local hint="${3:-Paste into v2rayN / v2rayNG / NekoBox → Import from clipboard}"
  local color_code="${4:-36}" # cyan default; 32 = green
  local w=${#uri} title_len=${#title} bar="" i
  ((w < title_len + 2)) && w=$((title_len + 2))
  w=$((w + 4))
  for ((i = 0; i < w; i++)); do bar+="─"; done

  local dim="" bold="" uri_color="" reset=""
  if _color_enabled; then
    dim=$'\033[2m'
    bold=$'\033[1m'
    uri_color=$'\033['"${color_code}"'m'
    reset=$'\033[0m'
  fi

  printf '\n'
  printf '%s%s%s\n' "${dim}" "${bar}" "${reset}"
  printf '%s  %s%s\n' "${bold}" "${title}" "${reset}"
  printf '%s  %s%s\n' "${dim}" "${hint}" "${reset}"
  printf '%s  %s%s\n' "${uri_color}" "${uri}" "${reset}"
  printf '%s%s%s\n' "${dim}" "${bar}" "${reset}"
  printf '\n'
}

[[ -f "${PROFILE_PATH}" ]] || fail "Profile file not found: ${PROFILE_PATH}"

if ! command -v docker >/dev/null 2>&1; then
  fail "Docker is not installed or not on PATH."
fi
if ! docker compose version >/dev/null 2>&1; then
  fail "docker compose is not available."
fi

ext="${PROFILE_PATH##*.}"
ext_lower="$(printf '%s' "${ext}" | tr '[:upper:]' '[:lower:]')"

cd "${REPO_ROOT}"

info "Applying VPN profile: ${PROFILE_PATH}"
if [[ "${ext_lower}" == "ovpn" ]]; then
  "${SCRIPT_DIR}/switch-openvpn-profile.sh" --profile-path "${PROFILE_PATH}" --env-path "${ENV_PATH}"
elif [[ "${ext_lower}" == "conf" ]]; then
  "${SCRIPT_DIR}/switch-wireguard-profile.sh" --profile-path "${PROFILE_PATH}" --env-path "${ENV_PATH}"
else
  fail "Unsupported profile extension: .${ext_lower} (use .ovpn or .conf only)"
fi
ok "VPN profile applied to .env and gluetun."

if [[ "${ext_lower}" == "ovpn" ]]; then
  custom_ovpn="${REPO_ROOT}/gluetun/custom.ovpn"
  if [[ -f "${custom_ovpn}" ]] && grep -qE '^[[:space:]]*auth-user-pass' "${custom_ovpn}"; then
    if ! grep -qE '^[[:space:]]*OVPN_USER=.+' "${ENV_PATH}" 2>/dev/null ||
      ! grep -qE '^[[:space:]]*OVPN_PASSWORD=.+' "${ENV_PATH}" 2>/dev/null; then
      fail "This OpenVPN profile requires auth-user-pass. Set OVPN_USER and OVPN_PASSWORD in .env."
    fi
    ok "OpenVPN credentials (OVPN_USER / OVPN_PASSWORD) are set in .env."
  fi
fi

if ! command -v node >/dev/null 2>&1; then
  fail "node is required to verify the VLESS UUID."
fi

has_uuid="$(node - "${REPO_ROOT}/xray/config.json" <<'NODE'
const fs = require('fs');
const p = process.argv[2];
const cfg = JSON.parse(fs.readFileSync(p, 'utf8'));
for (const ib of cfg.inbounds || []) {
  if (ib?.protocol === 'vless' && ib.settings?.clients?.[0]?.id) {
    process.stdout.write('yes');
    process.exit(0);
  }
}
NODE
)" || true

if [[ "${has_uuid}" != "yes" ]]; then
  info "No VLESS UUID in xray/config.json; generating..."
  "${SCRIPT_DIR}/generate-secrets.sh"
  ok "UUID written to xray/config.json."
else
  ok "VLESS client UUID found in xray/config.json."
fi

info "Starting Docker (gluetun + xray)..."
docker compose up -d --force-recreate gluetun xray

info "Waiting for VPN connection (up to ${VPN_WAIT_SECS}s)..."
deadline=$((SECONDS + VPN_WAIT_SECS))
vpn_ok=0
while ((SECONDS < deadline)); do
  if docker compose logs gluetun 2>/dev/null | grep -q "Initialization Sequence Completed"; then
    vpn_ok=1
    break
  fi
  if docker compose logs gluetun 2>/dev/null | tail -30 | grep -qE "ERROR VPN settings|Shutdown successful"; then
    break
  fi
  if ! docker inspect -f '{{.State.Running}}' vpn-upstream 2>/dev/null | grep -q true; then
    sleep 2
    if ! docker inspect -f '{{.State.Running}}' vpn-upstream 2>/dev/null | grep -q true; then
      break
    fi
  fi
  sleep 2
done

if [[ "${vpn_ok}" -ne 1 ]]; then
  fail "VPN did not come up. Last gluetun logs:
$(docker compose logs gluetun --tail 25 2>/dev/null || true)"
fi
ok "VPN tunnel (gluetun) is up."

if ! docker inspect -f '{{.State.Running}}' xray-lan-gateway 2>/dev/null | grep -q true; then
  fail "xray container is not running. Logs: $(docker compose logs xray --tail 15 2>/dev/null || true)"
fi
ok "Xray is running."

LAN_IP="${HOST}"
if [[ -z "${LAN_IP}" ]]; then
  LAN_IP="$("${SCRIPT_DIR}/get-lan-ip.sh" 2>/dev/null || true)"
fi

VLESS_LAN=""
VLESS_LOCAL=""
if [[ -n "${LAN_IP}" ]]; then
  VLESS_LAN="$("${SCRIPT_DIR}/print-vless-uri.sh" --host "${LAN_IP}" --remark "${REMARK}-lan")"
else
  info "Could not detect LAN IP; only the localhost VLESS link is shown."
fi
VLESS_LOCAL="$("${SCRIPT_DIR}/print-vless-uri.sh" --host 127.0.0.1 --remark "${REMARK}-local")"

log ""
log "========================================"
ok "All checks passed — stack is ready."
log "========================================"
log ""
if [[ -n "${VLESS_LAN}" ]]; then
  print_vless_box \
    "VLESS — phone / other devices on Wi-Fi (host ${LAN_IP})" \
    "${VLESS_LAN}" \
    "Paste into v2rayN / v2rayNG / NekoBox → Import from clipboard" \
    36
fi
print_vless_box \
  "VLESS — this PC only (127.0.0.1)" \
  "${VLESS_LOCAL}" \
  "Paste into v2rayN / v2rayNG / NekoBox → Import from clipboard" \
  32
log "Xray port is from .env (default 28443). Traffic exits through the VPN upstream."
log "Optional: after connecting a client, check egress IP at https://ipinfo.io/ip"
log "========================================"
