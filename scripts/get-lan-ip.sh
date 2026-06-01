#!/usr/bin/env bash
set -euo pipefail

# Prefer IPv4 source used for default route (closest to Windows: interface with default gateway).
if [[ -n "${LAN_IP:-}" ]]; then
  if [[ "${LAN_IP}" =~ ^(192\.168\.|10\.) ]]; then
    printf '%s\n' "${LAN_IP}"
    exit 0
  fi
fi

pick_lan_ipv4() {
  # Prefer real LAN (192.168.x) over VPN (e.g. 10.8.x) and Docker/WSL (172.16–31.x).
  local ip
  while IFS= read -r ip; do
    [[ "${ip}" =~ ^192\.168\. ]] && { printf '%s\n' "${ip}"; return 0; }
  done
  while IFS= read -r ip; do
    [[ "${ip}" =~ ^10\. ]] && [[ ! "${ip}" =~ ^10\.8\. ]] && { printf '%s\n' "${ip}"; return 0; }
  done
  return 1
}

if command -v ipconfig >/dev/null 2>&1; then
  # Windows (Git Bash): parse IPv4 from ipconfig output.
  mapfile -t _ipconfig_ips < <(
    ipconfig 2>/dev/null | awk -F: '/IPv4/ {gsub(/^[ \t]+/, "", $2); print $2}' |
      grep -E '^(192\.168\.|10\.)' | grep -vE '^172\.(1[6-9]|2[0-9]|3[0-1])\.'
  )
  if ((${#_ipconfig_ips[@]} > 0)); then
    cand="$(printf '%s\n' "${_ipconfig_ips[@]}" | pick_lan_ipv4)" || true
    [[ -n "${cand}" ]] && { printf '%s\n' "${cand}"; exit 0; }
  fi
fi

if command -v ip >/dev/null 2>&1; then
  mapfile -t _global_ips < <(
    ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 |
      grep -E '^(192\.168\.|10\.)' | grep -vE '^172\.(1[6-9]|2[0-9]|3[0-1])\.'
  )
  if ((${#_global_ips[@]} > 0)); then
    cand="$(printf '%s\n' "${_global_ips[@]}" | pick_lan_ipv4)" || true
    [[ -n "${cand}" ]] && { printf '%s\n' "${cand}"; exit 0; }
  fi
  src_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }')"
  if [[ -n "${src_ip}" && "${src_ip}" =~ ^(192\.168\.|10\.) && ! "${src_ip}" =~ ^10\.8\. ]]; then
    printf '%s\n' "${src_ip}"
    exit 0
  fi
fi

# macOS-style
if command -v route >/dev/null 2>&1 && [[ "$(uname -s)" == "Darwin" ]]; then
  src_ip="$(route -n get default 2>/dev/null | awk '/source:/{print $2; exit}')"
  [[ -n "${src_ip}" ]] && { printf '%s\n' "${src_ip}"; exit 0; }
fi

# Typical private subnets (fallback)
if command -v ip >/dev/null 2>&1; then
  mapfile -t _fallback_ips < <(
    ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 |
      grep -E '^(192\.168\.|10\.)' | grep -vE '^172\.(1[6-9]|2[0-9]|3[0-1])\.'
  )
  if ((${#_fallback_ips[@]} > 0)); then
    addr="$(printf '%s\n' "${_fallback_ips[@]}" | pick_lan_ipv4)" || true
    [[ -n "${addr}" ]] && { printf '%s\n' "${addr}"; exit 0; }
  fi
fi

if command -v hostname >/dev/null 2>&1 && hostname -I >/dev/null 2>&1; then
  mapfile -t _hostname_ips < <(
    hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^(192\.168\.|10\.)' | grep -vE '^172\.(1[6-9]|2[0-9]|3[0-1])\.'
  )
  if ((${#_hostname_ips[@]} > 0)); then
    cand="$(printf '%s\n' "${_hostname_ips[@]}" | pick_lan_ipv4)" || true
    [[ -n "${cand}" ]] && { printf '%s\n' "${cand}"; exit 0; }
  fi
fi

exit 1
