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
[[ -f "${ENV_PATH}" ]] || { echo ".env file not found: ${ENV_PATH}" >&2; exit 1; }

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
  if [[ -z "${ip}" ]] && command -v python3 >/dev/null 2>&1; then
    ip="$(python3 -c 'import socket,sys; print(socket.gethostbyname(sys.argv[1]))' "${host}" 2>/dev/null || true)"
  fi
  if [[ -z "${ip}" ]]; then
    echo "Failed to resolve endpoint host '${host}' to IPv4 (install dig, getent, or python3)." >&2
    return 1
  fi
  printf '%s' "${ip}"
}

endpoint_ip="$(resolve_ipv4 "${endpoint_host}")" || exit 1

python3 - "${ENV_PATH}" "${private_key}" "${address}" "${public_key}" "${endpoint_ip}" "${endpoint_port}" <<'PY'
import pathlib, re, sys

path = pathlib.Path(sys.argv[1])
keys = {
    "VPN_TYPE": "wireguard",
    "WG_PRIVATE_KEY": sys.argv[2],
    "WG_ADDRESSES": sys.argv[3],
    "WG_PUBLIC_KEY": sys.argv[4],
    "WG_ENDPOINT_IP": sys.argv[5],
    "WG_ENDPOINT_PORT": sys.argv[6],
}
text = path.read_text(encoding="utf-8")

def set_env(text: str, key: str, value: str) -> str:
    pattern = re.compile(rf"^(?m){re.escape(key)}=.*$")
    if pattern.search(text):
        return pattern.sub(f"{key}={value}", text)
    if text and not text.endswith("\n"):
        text += "\n"
    return text + f"{key}={value}\n"

for k, v in keys.items():
    text = set_env(text, k, v)

path.write_text(text, encoding="utf-8", newline="\n")
PY

echo "Switched profile from: ${PROFILE_PATH}"
echo "WG_ENDPOINT_IP: ${endpoint_ip}"
echo "WG_ENDPOINT_PORT: ${endpoint_port}"

if [[ "${RESTART_STACK}" -eq 1 ]]; then
  echo "Restarting Docker stack..."
  (cd "${REPO_ROOT}" && docker compose up -d --force-recreate gluetun xray && docker compose ps)
fi
