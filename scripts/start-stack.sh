#!/usr/bin/env bash
set -euo pipefail

PROFILE_PATH=""
HOST=""
REMARK="gluetun-lan"
ENV_PATH="./.env"
VPN_WAIT_SECS=120

usage() {
  echo "Usage: $0 --profile-path <profiles/file.conf|.ovpn> [--host <ip>] [--remark <label>] [--env-path <path>]" >&2
  echo "  Applies VPN profile, starts Docker (gluetun + xray), waits for VPN, prints VLESS URI." >&2
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
fail() { log "[خطا] $*"; exit 1; }

[[ -f "${PROFILE_PATH}" ]] || fail "فایل پروفایل پیدا نشد: ${PROFILE_PATH}"

if ! command -v docker >/dev/null 2>&1; then
  fail "Docker نصب نیست یا در PATH نیست."
fi
if ! docker compose version >/dev/null 2>&1; then
  fail "docker compose در دسترس نیست."
fi

ext="${PROFILE_PATH##*.}"
ext_lower="$(printf '%s' "${ext}" | tr '[:upper:]' '[:lower:]')"

cd "${REPO_ROOT}"

info "اعمال پروفایل VPN: ${PROFILE_PATH}"
if [[ "${ext_lower}" == "ovpn" ]]; then
  "${SCRIPT_DIR}/switch-openvpn-profile.sh" --profile-path "${PROFILE_PATH}" --env-path "${ENV_PATH}"
elif [[ "${ext_lower}" == "conf" ]]; then
  "${SCRIPT_DIR}/switch-wireguard-profile.sh" --profile-path "${PROFILE_PATH}" --env-path "${ENV_PATH}"
else
  fail "پسوند پروفایل پشتیبانی نمی‌شود: .${ext_lower} (فقط .ovpn یا .conf)"
fi
ok "پروفایل VPN روی .env و gluetun اعمال شد."

if [[ "${ext_lower}" == "ovpn" ]]; then
  custom_ovpn="${REPO_ROOT}/gluetun/custom.ovpn"
  if [[ -f "${custom_ovpn}" ]] && grep -qE '^[[:space:]]*auth-user-pass' "${custom_ovpn}"; then
    if ! grep -qE '^[[:space:]]*OVPN_USER=.+' "${ENV_PATH}" 2>/dev/null ||
      ! grep -qE '^[[:space:]]*OVPN_PASSWORD=.+' "${ENV_PATH}" 2>/dev/null; then
      fail "این پروفایل OpenVPN به auth-user-pass نیاز دارد. در .env مقدار OVPN_USER و OVPN_PASSWORD را پر کنید."
    fi
    ok "اعتبار OpenVPN (OVPN_USER / OVPN_PASSWORD) در .env تنظیم شده است."
  fi
fi

if ! command -v node >/dev/null 2>&1; then
  fail "برای بررسی UUID به node نیاز است."
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
  info "UUID در xray/config.json نیست؛ در حال ساخت..."
  "${SCRIPT_DIR}/generate-secrets.sh"
  ok "UUID ساخته و در xray/config.json ذخیره شد."
else
  ok "UUID کلاینت VLESS در xray/config.json موجود است."
fi

info "بالا آوردن Docker (gluetun + xray)..."
docker compose up -d --force-recreate gluetun xray

info "منتظر اتصال VPN هستیم (حداکثر ${VPN_WAIT_SECS} ثانیه)..."
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
  fail "VPN وصل نشد. آخرین لاگ gluetun:
$(docker compose logs gluetun --tail 25 2>/dev/null || true)"
fi
ok "تونل VPN (gluetun) برقرار است."

if ! docker inspect -f '{{.State.Running}}' xray-lan-gateway 2>/dev/null | grep -q true; then
  fail "کانتینر xray در حال اجرا نیست. لاگ: $(docker compose logs xray --tail 15 2>/dev/null || true)"
fi
ok "سرویس Xray در حال اجرا است."

print_args=(--remark "${REMARK}")
[[ -n "${HOST}" ]] && print_args+=(--host "${HOST}")

VLESS_URI="$("${SCRIPT_DIR}/print-vless-uri.sh" "${print_args[@]}")"
LAN_IP="$("${SCRIPT_DIR}/get-lan-ip.sh" 2>/dev/null || true)"

log ""
log "========================================"
ok "همه چیز درست است — استک آماده است."
log "========================================"
log ""
log "این لینک VLESS را در کلاینت (v2rayN / v2rayNG / NekoBox) کپی کنید:"
log "  Import from clipboard / وارد کردن از کلیپ‌بورد"
log ""
log "${VLESS_URI}"
log ""
if [[ -n "${LAN_IP}" && -z "${HOST}" ]]; then
  log "آدرس LAN میزبان: ${LAN_IP} — کلاینت‌های دیگر روی همان Wi‑Fi باید به این IP وصل شوند."
elif [[ -n "${HOST}" ]]; then
  log "آدرس در لینک: ${HOST} (دستی تنظیم شده)"
fi
log "پورت Xray از .env (معمولاً 28443). ترافیک از تونل VPN upstream خارج می‌شود."
log ""
log "بررسی اختیاری: بعد از اتصال کلاینت، IP خروجی را ببینید — https://ipinfo.io/ip"
log "========================================"
