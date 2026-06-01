#!/usr/bin/env bash
set -euo pipefail

# Prefer IPv4 source used for default route (closest to Windows: interface with default gateway).
if [[ -n "${LAN_IP:-}" ]]; then
  if [[ "${LAN_IP}" =~ ^(192\.168\.|10\.) ]]; then
    printf '%s\n' "${LAN_IP}"
    exit 0
  fi
fi

if command -v ipconfig >/dev/null 2>&1; then
  # Windows (Git Bash): parse IPv4 from ipconfig output.
  # Usually: "IPv4 Address. . . . . . . . . . . : 192.168.1.10"
  cand="$(ipconfig 2>/dev/null | awk -F: '/IPv4/ {gsub(/^[ \t]+/, "", $2); print $2}' | grep -E '^(192\.168\.|10\.)' | head -n1)"
  [[ -n "${cand}" ]] && { printf '%s\n' "${cand}"; exit 0; }
fi

if command -v ip >/dev/null 2>&1; then
  src_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }')"
  [[ -n "${src_ip}" ]] && { printf '%s\n' "${src_ip}"; exit 0; }
fi

# macOS-style
if command -v route >/dev/null 2>&1 && [[ "$(uname -s)" == "Darwin" ]]; then
  src_ip="$(route -n get default 2>/dev/null | awk '/source:/{print $2; exit}')"
  [[ -n "${src_ip}" ]] && { printf '%s\n' "${src_ip}"; exit 0; }
fi

# Typical private subnets (fallback)
if command -v ip >/dev/null 2>&1; then
  addr="$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -E '^(192\.168\.|10\.)' | head -n1)"
  [[ -n "${addr}" ]] && { printf '%s\n' "${addr}"; exit 0; }
fi

if command -v hostname >/dev/null 2>&1 && hostname -I >/dev/null 2>&1; then
  cand="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^(192\.168\.|10\.)' | head -n1)"
  [[ -n "${cand}" ]] && { printf '%s\n' "${cand}"; exit 0; }
fi

exit 1
