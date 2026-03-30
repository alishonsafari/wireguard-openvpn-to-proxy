# راه‌اندازی Gluetun + Xray (شبکهٔ داخلی)

با این پروژه یک سرور سبک **Xray** پشت **Gluetun** در Docker بالا می‌آید؛ دستگاه‌های روی LAN به پورت Xray روی ماشین میزبان وصل می‌شوند و خروجی‌شان از مسیر VPN upstream داخل کانتینر می‌رود.

**English:** [README.md](README.md)

## ایدهٔ کلی

1. کانتینر `gluetun` به VPN upstream وصل می‌شود (ترجیحاً WireGuard).
2. کانتینر `xray` در همان استک Docker اجرا می‌شود.
3. کلاینت‌های LAN به آی‌پی محلی میزبان و پورت منتشرشده وصل می‌شوند.
4. ترافیک از تونل VPN عبور می‌کند.

---

## پیش‌نیاز

- Docker و `docker compose` نصب و در حال اجرا.
- میزبان و کلاینت‌ها در یک شبکهٔ LAN (برای سناریوی پیشنهادی).
- پروفایل WireGuard (فایل `.conf`) یا در صورت نیاز OpenVPN.

**اسکریپت‌ها** برای هر کار معمولاً دو نسخه دارند: **Bash** (`*.sh`) و **PowerShell** (`*.ps1`).

- **Bash:** لینوکس، macOS، Git Bash، WSL — از **ریشهٔ مخزن**: `./scripts/...`؛ در صورت نیاز `chmod +x scripts/*.sh`
- **PowerShell:** ویندوز؛ در صورت خطای اجرای اسکریپت: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

---

## گام ۱ — ساخت فایل `.env`

از **ریشهٔ پروژه** (جایی که `docker-compose.yml` است) فقط این دستور را بزن:

```bash
cp .env.example .env
```

```powershell
Copy-Item .env.example .env
```

بعداً می‌توانی پورتها، `TZ` و مقادیر VPN را در `.env` عوض کنی. مراحل بعدی اگر از فایل پروفایل WireGuard استفاده کنی، فیلدهای `WG_*` را خودکار پر می‌کنند.

---

## گام ۲ — کپی پروفایل‌های WireGuard داخل `profiles/`

فایل‌های `.conf` که از پنل VPN گرفتی (یا خروجی WireGuard) را در پوشهٔ **`profiles/`** بگذار، مثلاً:

- `profiles/VS7.conf`
- `profiles/IR.conf`

برای هر سرور/لوکیشن یک فایل جدا نگه دار تا بعداً با اسکریپت بین‌شان سوئیچ کنی.

---

## گام ۳ — اعمال پروفایل روی `.env`، ساخت UUID، و بالا آوردن سرویس

همهٔ دستورها را از **ریشهٔ مخزن** اجرا کن.

### ۳الف — پر کردن `.env` از روی پروفایل WireGuard

این اسکریپت کلیدها و `Endpoint` را می‌خواند، در صورت نیاز نام دامنهٔ endpoint را به IPv4 حل می‌کند و `WG_*` و `VPN_TYPE=wireguard` را در `.env` می**نویسد**:

```bash
./scripts/switch-wireguard-profile.sh --profile-path ./profiles/VS7.conf --restart-stack
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\switch-wireguard-profile.ps1 -ProfilePath .\profiles\VS7.conf -RestartStack
```

- برای **اولین بار** که هنوز استک بالا نیست، می‌توانی `--restart-stack` / `-RestartStack` را نگذاری.
- اگر استک از قبل در حال اجراست و می‌خواهی `gluetun` و `xray` دوباره ساخته شوند، این سوئیچ را بگذار.

### ۳ب — تولید UUID و نوشتن در `xray/config.json`

قبل از گرفتن لینک اشتراک، یک بار (یا بعد از هر بار که خواستی UUID عوض شود) اجرا کن:

```bash
./scripts/generate-secrets.sh
```

```powershell
.\scripts\generate-secrets.ps1
```

### ۳ج — بالا آوردن داکر

```bash
docker compose up -d
```

مشاهدهٔ لاگ در صورت نیاز:

```bash
docker compose logs -f gluetun
docker compose logs -f xray
```

**OpenVPN:** در `.env` بگذار `VPN_TYPE=openvpn`، فایل را در `gluetun/custom.ovpn` قرار بده و در صورت نیاز `OVPN_*` را پر کن — مرحلهٔ پروفایل WireGuard لازم نیست.

---

## گام ۴ — لینک VLESS برای کپی در کلاینت (NekoBox / v2rayNG / v2rayN)

سرور روی میزبان روی پورت مثل **۲۸۴۴۳** (مقدار `XRAY_PORT` در `.env`) گوش می‌دهد. برای ساخت یک URI استاندارد **VLESS** (TCP روی LAN، بدون TLS) از اسکریپت زیر استفاده کن؛ خروجی را **کامل کپی** کن و در اپ کلاینت گزینهٔ **وارد کردن از کلیپ‌بورد** / **Import link** را بزن:

```bash
./scripts/print-vless-uri.sh
```

```powershell
.\scripts\print-vless-uri.ps1
```

به‌طور پیش‌فرض آی‌پی داخل لینک با `get-lan-ip` پر می‌شود. اگر لازم بود دستی بدهی:

```bash
./scripts/print-vless-uri.sh --host 192.168.1.10 --remark "خانه"
```

```powershell
.\scripts\print-vless-uri.ps1 -HostAddr 192.168.1.10 -Remark "home"
```

**نکته:** این اسکریپت UUID را از اولین inbound از نوع `vless` در `xray/config.json` می‌خواند؛ پس حتماً قبلش `generate-secrets` را اجرا کرده باشی.

### لینک دانلود کلاینت‌ها

- **NekoBox (اندروید):** [https://github.com/MatsuriDayo/NekoBoxForAndroid](https://github.com/MatsuriDayo/NekoBoxForAndroid)
- **v2rayNG (اندروید):** [https://github.com/2dust/v2rayNG](https://github.com/2dust/v2rayNG)
- **v2rayN (ویندوز):** [https://github.com/2dust/v2rayN](https://github.com/2dust/v2rayN)

بعد از وصل شدن می‌توانی با [https://ipinfo.io/ip](https://ipinfo.io/ip) ببینی IP خروجی همان VPN upstream است یا نه.

---

## باز کردن پورت روی فایروال

**ویندوز (CMD با دسترسی ادمین، بدون PowerShell):**

```bat
netsh advfirewall firewall add rule name="Xray LAN 28443" dir=in action=allow protocol=TCP localport=28443
```

اگر `XRAY_PORT` را عوض کردی، `localport` را هماهنگ کن.

**لینوکس (مثال UFW):**

```bash
sudo ufw allow 28443/tcp
```

---

## جدول اسکریپت‌های کمکی

| اسکریپت | کار |
|---------|-----|
| `get-lan-ip.*` | چاپ یک آی‌پی LAN محتمل |
| `switch-wireguard-profile.*` | پر کردن `WG_*` در `.env` از `.conf` |
| `generate-secrets.*` | UUID جدید در `xray/config.json` |
| `print-vless-uri.*` | چاپ لینک `vless://` برای کلاینت |

---

## Routing فعلی در `xray/config.json`

- تبلیغات با `geosite:category-ads-all` بلاک می‌شود.
- شبکهٔ خصوصی (`private`) مستقیم مدیریت می‌شود.
- خروجی پیش‌فرض `freedom` است و از مسیر VPN کانتینر تبعیت می‌کند.

---

## نکات مهم

- این کانفیگ برای **LAN مورد اعتماد** است؛ روی inbound عمومی TLS / REALITY ندارد.
- روی ویندوز host network مثل لینوکس نیست؛ استفاده از port mapping به‌همراه Gluetun روش معمول است.
