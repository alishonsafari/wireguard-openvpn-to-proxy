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

## شروع سریع (یک دستور)

فایل VPN را در `profiles/` بگذار. اگر `.ovpn` شما `auth-user-pass` دارد، قبلش در `.env` مقدار `OVPN_USER` و `OVPN_PASSWORD` را پر کن، بعد:

```bash
./scripts/start-stack.sh --profile-path ./profiles/Smart11MTN-nl.ovpn
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-stack.ps1 -ProfilePath .\profiles\Smart11MTN-nl.ovpn
```

WireGuard:

```bash
./scripts/start-stack.sh --profile-path ./profiles/VS7.conf
```

اسکریپت پروفایل را اعمال می‌کند، Docker (`gluetun` + `xray`) را بالا می‌آورد، تا وصل شدن VPN صبر می‌کند و در پایان **دو لینک VLESS** را داخل **کادر و رنگ** (فیروزه‌ای = LAN، سبز = localhost) چاپ می‌کند (پیام‌های کنسول انگلیسی):

- **LAN** — IP همین سیستم روی Wi‑Fi؛ برای **گوشی یا دستگاه دیگر** روی همان شبکه در v2rayNG / NekoBox paste کنید
- **127.0.0.1** — فقط برای تست کلاینت روی **همین PC**

اختیاری: `--host <ip>` / `-HostAddr <ip>` اگر IP تشخیص‌داده‌شده برای LAN اشتباه بود (مثلاً آداپتور VPN به‌جای Wi‑Fi).

**پیشنهادی:** برای استفادهٔ معمول همان `start-stack` کافی است — مسیر پروفایل را می‌دهی، Docker بالا می‌آید، لینک VLESS چاپ می‌شود.

**حالت manual:** گام‌های پایین (گام ۱ تا ۴) همان کار را **دستور به دستور** انجام می‌دهند (`switch-*-profile`، `generate-secrets`، `docker compose up`، `print-vless-uri`). وقتی بین مراحل می‌خواهی چیزی را جداگانه عوض کنی یا لاگ بگیری (مثلاً بعد از switch فقط `.env` را ویرایش کنی، فقط UUID عوض شود، Docker بدون اعمال دوبارهٔ پروفایل restart شود) از manual استفاده کن. اگر `start-stack` برایت جواب می‌دهد، لازم نیست manual بروی.

---

## راه‌اندازی دستی (گام‌به‌گام)

اگر **شروع سریع** را زدی و استک بالا است، این بخش را رد کن.

## گام ۱ — فایل `.env`

`docker compose`، اسکریپت لینک VLESS و Gluetun به یک فایل **`.env`** در ریشهٔ مخزن نیاز دارند. داخل مخزن فقط **`.env.example`** هست؛ خودش به‌تنهایی جایگزین `.env` نمی‌شود مگر اینکه آن را کپی کنی یا اسکریپت برایت بسازد.

**روش الف — دستی** (از ریشهٔ پروژه):

```bash
cp .env.example .env
```

```powershell
Copy-Item .env.example .env
```

**روش ب — فعلاً کپی نکن:** در **گام ۳** اسکریپت `switch-wireguard-profile` اگر `.env` وجود نداشته باشد، خودش آن را با **کپی از `.env.example`** می‌سازد و بعد فیلدهای `WG_*` را از پروفایل WireGuard پر می‌کند.

یعنی برای مسیر معمول (WireGuard + همان اسکریپت، مسیر پیش‌فرض `.env`) همان گام ۳ هم نزدیک به «ساخت `.env` با یک دستور» است؛ فقط اگر **فقط OpenVPN** داری و آن اسکریپت را اجرا نمی‌کنی، حتماً با روش الف `.env` را بساز و دستی پر کن.

---

## گام ۲ — کپی پروفایل‌های WireGuard داخل `profiles/`

فایل‌های `.conf` که از پنل VPN گرفتی (یا خروجی WireGuard) را در پوشهٔ **`profiles/`** بگذار، مثلاً:

- `profiles/VS7.conf`
- `profiles/IR.conf`

برای هر سرور/لوکیشن یک فایل جدا نگه دار تا بعداً با اسکریپت بین‌شان سوئیچ کنی.

---

## گام ۳ — اعمال پروفایل روی `.env`، ساخت UUID، و بالا آوردن سرویس

همان مراحلی که `start-stack` یک‌جا انجام می‌دهد، اینجا جدا است. همهٔ دستورها را از **ریشهٔ مخزن** اجرا کن.

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
./scripts/print-vless-uri.sh --host 127.0.0.1
```

```powershell
.\scripts\print-vless-uri.ps1 --host 127.0.0.1
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
| `start-stack.*` | **همه‌کاره:** اعمال پروفایل، بالا آوردن Docker، انتظار VPN، چاپ لینک VLESS |
| `get-lan-ip.*` | چاپ یک آی‌پی LAN محتمل |
| `switch-wireguard-profile.*` | پر کردن `WG_*` در `.env` از `.conf` |
| `switch-openvpn-profile.*` | کپی `.ovpn` به `gluetun/custom.ovpn` و `VPN_TYPE=openvpn` |
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
