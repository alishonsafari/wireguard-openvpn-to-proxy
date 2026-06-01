#!/usr/bin/env bash
set -euo pipefail

PROFILE_PATH=""
ENV_PATH="./.env"
RESTART_STACK=0

usage() {
  echo "Usage: $0 --profile-path <path> [--env-path <path>] [--restart-stack]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile-path)
      PROFILE_PATH="${2:-}"
      shift 2
      ;;
    --env-path)
      ENV_PATH="${2:-}"
      shift 2
      ;;
    --restart-stack)
      RESTART_STACK=1
      shift
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

[[ -f "${PROFILE_PATH}" ]] || { echo "OpenVPN profile not found: ${PROFILE_PATH}" >&2; exit 1; }

if [[ ! -f "${ENV_PATH}" ]]; then
  example="${REPO_ROOT}/.env.example"
  if [[ -f "${example}" ]]; then
    cp "${example}" "${ENV_PATH}"
    echo "Created ${ENV_PATH} from .env.example" >&2
  else
    echo ".env not found at ${ENV_PATH} and repo has no .env.example to copy." >&2
    exit 1
  fi
fi

resolve_ipv4() {
  local host="$1"
  if [[ "${host}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s' "${host}"
    return 0
  fi
  local ip=""
  if command -v node >/dev/null 2>&1; then
    ip="$(node - "${host}" <<'NODE' 2>/dev/null || true
const dns = require('dns');
const host = process.argv[2];
dns.resolve4(host, (err, addrs) => {
  if (err || !addrs || !addrs.length) process.exit(1);
  process.stdout.write(addrs[0]);
});
NODE
)"
  fi
  if [[ -z "${ip}" ]] && command -v dig >/dev/null 2>&1; then
    ip="$(dig +short "${host}" A 2>/dev/null | grep -E '^[0-9.]+$' | head -n1)"
  fi
  if [[ -z "${ip}" ]] && command -v getent >/dev/null 2>&1; then
    ip="$(getent ahostsv4 "${host}" 2>/dev/null | awk '/STREAM/ {print $1; exit}')"
  fi
  if [[ -z "${ip}" ]] && command -v nslookup >/dev/null 2>&1; then
    # Linux: "Address: 1.2.3.4" after answer Name; Windows: "Addresses:" then indented IPs
    ip="$(nslookup -type=A "${host}" 2>/dev/null | awk '
      /^Name:[[:space:]]*/ { in_answer = 1; next }
      in_answer && /^Address:[[:space:]]*/ && $2 !~ /^[0-9.]+:[0-9]+$/ { print $2; exit }
      in_answer && /^Addresses:/ { in_addrs = 1; next }
      in_addrs && /^[[:space:]]+[0-9]/ {
        gsub(/^[[:space:]]+/, "")
        print $1
        exit
      }
    ')"
  fi
  if [[ -z "${ip}" ]]; then
    echo "Failed to resolve OpenVPN remote host '${host}' to IPv4." >&2
    return 1
  fi
  printf '%s' "${ip}"
}

# Gluetun requires numeric IPs in `remote` lines (no DNS before tunnel is up).
patch_remote_lines_to_ipv4() {
  local src="$1" dst="$2"
  local line host port ip rest
  : >"${dst}"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" =~ ^[[:space:]]*remote[[:space:]]+([^[:space:]]+)([[:space:]]+.*)?$ ]]; then
      host="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[2]:-}"
      if [[ "${rest}" =~ ^[[:space:]]+([0-9]+) ]]; then
        port="${BASH_REMATCH[1]}"
      else
        port=""
      fi
      ip="$(resolve_ipv4 "${host}")" || return 1
      if [[ -n "${port}" ]]; then
        printf 'remote %s %s\n' "${ip}" "${port}" >>"${dst}"
      else
        printf 'remote %s%s\n' "${ip}" "${rest}" >>"${dst}"
      fi
      if [[ "${host}" != "${ip}" ]]; then
        echo "Resolved remote ${host} -> ${ip}" >&2
      fi
    else
      printf '%s\n' "${line}" >>"${dst}"
    fi
  done <"${src}"
}

GLUETUN_DIR="${REPO_ROOT}/gluetun"
CUSTOM_OVPN="${GLUETUN_DIR}/custom.ovpn"
mkdir -p "${GLUETUN_DIR}"
patch_remote_lines_to_ipv4 "${PROFILE_PATH}" "${CUSTOM_OVPN}"

if ! command -v node >/dev/null 2>&1; then
  echo "node is required for updating .env (missing node)." >&2
  exit 1
fi

node - "${ENV_PATH}" <<'NODE'
const fs = require('fs');
const envPath = process.argv[2];
let text = fs.readFileSync(envPath, 'utf8');

function setEnv(key, value) {
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp('^' + escapedKey + '=.*$', 'm');
  if (re.test(text)) {
    text = text.replace(re, `${key}=${value}`);
  } else {
    if (text.length > 0 && !text.endsWith('\n')) text += '\n';
    text += `${key}=${value}\n`;
  }
}

setEnv('VPN_TYPE', 'openvpn');
fs.writeFileSync(envPath, text, 'utf8');
NODE

echo "Switched to OpenVPN profile: ${PROFILE_PATH}"
echo "Config copied to: ${CUSTOM_OVPN}"
echo "VPN_TYPE=openvpn in ${ENV_PATH}"

if grep -qE '^auth-user-pass' "${CUSTOM_OVPN}" 2>/dev/null; then
  if ! grep -qE '^OVPN_USER=.+' "${ENV_PATH}" 2>/dev/null || ! grep -qE '^OVPN_PASSWORD=.+' "${ENV_PATH}" 2>/dev/null; then
    echo "" >&2
    echo "This profile uses auth-user-pass. Set OVPN_USER and OVPN_PASSWORD in ${ENV_PATH} before starting gluetun." >&2
  fi
fi

if [[ "${RESTART_STACK}" -eq 1 ]]; then
  echo "Restarting Docker stack..."
  (cd "${REPO_ROOT}" && docker compose up -d --force-recreate gluetun xray && docker compose ps)
fi
