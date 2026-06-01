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

[[ -f "${PROFILE_PATH}" ]] || { echo "WireGuard profile not found: ${PROFILE_PATH}" >&2; exit 1; }

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

get_ini_value() {
  local key="$1" file="$2"
  # First non-empty value for key (case-insensitive key match), INI-style line.
  awk -v k="$key" '
    tolower($0) ~ "^[[:space:]]*" tolower(k) "[[:space:]]*=" {
      sub(/^[[:space:]]*[^=]+=[[:space:]]*/, "")
      sub(/\r$/, "")
      sub(/[[:space:]]+$/, "")
      if (length > 0) { print; exit }
    }
  ' "${file}"
}

private_key="$(get_ini_value "PrivateKey" "${PROFILE_PATH}")"
address="$(get_ini_value "Address" "${PROFILE_PATH}")"
public_key="$(get_ini_value "PublicKey" "${PROFILE_PATH}")"
endpoint="$(get_ini_value "Endpoint" "${PROFILE_PATH}")"

if [[ -z "${private_key}" || -z "${address}" || -z "${public_key}" || -z "${endpoint}" ]]; then
  echo "Profile is missing one of required keys: PrivateKey, Address, PublicKey, Endpoint" >&2
  exit 1
fi

if [[ "${endpoint}" != *:* ]]; then
  echo "Endpoint format is invalid: ${endpoint}" >&2
  exit 1
fi

endpoint_host="${endpoint%:*}"
endpoint_port="${endpoint##*:}"

# host may be IPv6 with colons — if so, endpoint split above is wrong; WireGuard consumer exports usually host:port for IPv4/hostname.
if [[ "${endpoint_host}" == *:* && "${endpoint_host}" != *.* ]]; then
  echo "IPv6 endpoint parsing is not supported; use a hostname or IPv4 in the profile Endpoint." >&2
  exit 1
fi

resolve_ipv4() {
  local host="$1"
  if [[ "${host}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s' "${host}"
    return 0
  fi
  local ip=""
  if command -v dig >/dev/null 2>&1; then
    ip="$(dig +short "${host}" A 2>/dev/null | grep -E '^[0-9.]+$' | head -n1)"
  fi
  if [[ -z "${ip}" ]] && command -v getent >/dev/null 2>&1; then
    ip="$(getent ahostsv4 "${host}" 2>/dev/null | awk '/STREAM/ {print $1; exit}')"
  fi
  if [[ -z "${ip}" ]] && command -v nslookup >/dev/null 2>&1; then
    # Example line: "Address:  85.198.17.66"
    # nslookup معمولاً دو بار "Address:" چاپ می‌کند:
    # 1) آدرس DNS server (لوکال مثل 192.168.x.x)
    # 2) آدرس رکورد موردنظر (مورد نیاز ما)
    # بنابراین فقط Address بعد از بخش "Name:" را می‌گیریم.
    ip="$(nslookup -type=A "${host}" 2>/dev/null | awk '
      /^Name:[[:space:]]*/ {in_answer=1; next}
      in_answer && /^Address:[[:space:]]*/ {print $2; exit}
    ')"
  fi
  if [[ -z "${ip}" ]]; then
    echo "Failed to resolve endpoint host '${host}' to IPv4 (install dig/getent, or use DNS with nslookup)." >&2
    return 1
  fi
  printf '%s' "${ip}"
}

endpoint_ip="$(resolve_ipv4 "${endpoint_host}")" || exit 1

if ! command -v node >/dev/null 2>&1; then
  echo "node is required for updating .env (missing node)." >&2
  exit 1
fi

node - "${ENV_PATH}" "${private_key}" "${address}" "${public_key}" "${endpoint_ip}" "${endpoint_port}" <<'NODE'
const fs = require('fs');

// process.argv = [node, '-', envPath, privateKey, addr, publicKey, endpointIp, endpointPort]
const [envPath, privateKey, addr, publicKey, endpointIp, endpointPort] = process.argv.slice(2);
let text = fs.readFileSync(envPath, 'utf8');

function setEnv(key, value) {
  // Escape key for RegExp (so keys like WG_PUBLIC_KEY work safely).
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp('^' + escapedKey + '=.*$', 'm');
  if (re.test(text)) {
    text = text.replace(re, `${key}=${value}`);
  } else {
    if (text.length > 0 && !text.endsWith('\n')) text += '\n';
    text += `${key}=${value}\n`;
  }
}

setEnv('VPN_TYPE', 'wireguard');
setEnv('WG_PRIVATE_KEY', privateKey);
setEnv('WG_ADDRESSES', addr);
setEnv('WG_PUBLIC_KEY', publicKey);
setEnv('WG_ENDPOINT_IP', endpointIp);
setEnv('WG_ENDPOINT_PORT', endpointPort);

fs.writeFileSync(envPath, text, 'utf8');
NODE

echo "Switched profile from: ${PROFILE_PATH}"
echo "WG_ENDPOINT_IP: ${endpoint_ip}"
echo "WG_ENDPOINT_PORT: ${endpoint_port}"

if [[ "${RESTART_STACK}" -eq 1 ]]; then
  echo "Restarting Docker stack..."
  (cd "${REPO_ROOT}" && docker compose up -d --force-recreate gluetun xray && docker compose ps)
fi
