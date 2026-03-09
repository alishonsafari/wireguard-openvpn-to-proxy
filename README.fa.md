# راه‌اندازی Xray داخلی با Docker (روی ویندوز)

این پروژه یک `Xray` سرور سبک برای شبکه داخلی می‌سازد تا گوشی/لپ‌تاپ‌ها به سیستم شما وصل شوند و از مسیر خروجی VPN عبور کنند.

## ایده اصلی

1. کانتینر `gluetun` به VPN upstream وصل می‌شود (WireGuard یا OpenVPN).
2. کانتینر `Xray` روی همان network stack اجرا می‌شود.
3. کلاینت‌های شبکه داخلی به `Xray` وصل می‌شوند.
4. خروجی کلاینت‌ها از تونل VPN داخل Docker عبور می‌کند.

---

## 1) پیش‌نیاز

- Docker Desktop نصب و فعال باشد.
- سیستم و گوشی در یک LAN باشند (برای شروع داخلی).
- اطلاعات WireGuard یا OpenVPN از پنل سرویس VPN داشته باشی.

## 2) تنظیم UUID

در مسیر پروژه اجرا کن:

```powershell
.\scripts\generate-secrets.ps1
```

این دستور UUID امن می‌سازد و داخل `xray/config.json` جایگزین می‌کند.

## 3) انتخاب پروتکل VPN (بر اساس عکس شما)

بین گزینه‌های `L2TP / CISCO / WIREGUARD / OPENVPN / IKEV2`:

- پیشنهاد اصلی: `WIREGUARD` (سریع‌تر، ساده‌تر برای Docker، سربار کمتر)
- گزینه جایگزین: `OPENVPN` (اگر فقط `.ovpn` داری)
- `L2TP / IKEV2 / CISCO` برای Docker این سناریو پیچیده‌تر و کم‌ارزش‌تر هستند.

## 4) تنظیم `.env`

```powershell
copy .env.example .env
```

سپس فایل `.env` را کامل کن:

- اگر `WireGuard` داری: مقادیر `WG_*` را از پنل VPN پر کن و `VPN_TYPE=wireguard`
- اگر فقط `OpenVPN` داری: `VPN_TYPE=openvpn` بگذار و فایل `custom.ovpn` را در مسیر `gluetun/custom.ovpn` قرار بده

## 5) بالا آوردن سرویس

```powershell
docker compose up -d
docker compose logs -f gluetun
docker compose logs -f xray
```

## 6) باز کردن پورت روی فایروال ویندوز

```powershell
New-NetFirewallRule -DisplayName "Xray LAN 28443" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 28443
```

## 7) ساخت کانکشن در کلاینت (گوشی/سیستم)

در کلاینت‌هایی مثل `NekoBox` / `v2rayN`:

- Protocol: `VLESS`
- Address: آی‌پی LAN سیستم ویندوز (مثلا `192.168.1.10`)
- Port: `28443` (یا مقدار `XRAY_PORT` در `.env`)
- UUID: همان مقدار داخل `xray/config.json`
- Encryption: `none`
- Transport: `tcp`
- TLS: خاموش (برای LAN داخلی)

بعد از اتصال، تست کن:
- `https://ipinfo.io/ip`
- باید IP خروجی مربوط به VPN upstream داخل Docker باشد.

---

## Routing فعلی در Xray

در `xray/config.json`:

- تبلیغات با `geosite:category-ads-all` بلاک می‌شود.
- شبکه خصوصی (`private`) مستقیم handled می‌شود.
- بقیه ترافیک outbound عادی `freedom` است (که از تونل VPN کانتینر تبعیت می‌کند).

اگر خواستی routing پیچیده‌تر (لیست دامنه سفارشی، split جدا، policy برای اپ‌ها) اضافه کنیم، روی همین فایل توسعه می‌دهیم.

---

## نکات مهم

- این کانفیگ برای **LAN داخلی** است و TLS/REALITY ندارد.
- اگر بخواهی از بیرون خانه هم وصل شوی، باید نسخه امن اینترنتی (VLESS + REALITY + محدودسازی فایروال) اضافه کنیم.
- روی ویندوز، host network مثل لینوکس نداریم؛ بنابراین `gluetun + port mapping` روش درست است.
