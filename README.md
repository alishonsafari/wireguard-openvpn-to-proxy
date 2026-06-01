# Gluetun + Xray (LAN)

Lightweight [Xray](https://github.com/XTLS/Xray-core) behind [Gluetun](https://github.com/qdm12/gluetun) in Docker: devices on your LAN connect to Xray on the host, and egress goes through the VPN tunnel inside the container stack.

**Persian:** [README.fa.md](README.fa.md)

## How it works

1. `gluetun` connects to the upstream VPN (WireGuard or OpenVPN).
2. `xray` shares the same Docker network namespace (or routed via Gluetun, depending on your compose setup).
3. LAN clients connect to the published Xray port on the host.
4. Their traffic exits through the upstream VPN.

---

## Prerequisites

- Docker with Compose (`docker compose`).
- Host and clients on the same LAN (for this internal setup).
- A WireGuard `.conf` or an OpenVPN `.ovpn` profile from your provider.

Helper scripts exist in both **Bash** (`.sh`) and **PowerShell** (`.ps1`).

- **Bash:** Linux, macOS, Git Bash, WSL. From the repo root: `./scripts/...`. If needed: `chmod +x scripts/*.sh`
- **PowerShell:** Windows. If execution policy blocks scripts: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

---

## Quick start (one command)

Put your VPN file in `profiles/`, set `OVPN_USER` / `OVPN_PASSWORD` in `.env` first if the `.ovpn` uses `auth-user-pass`, then run:

```bash
./scripts/start-stack.sh --profile-path ./profiles/Smart11MTN-nl.ovpn
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-stack.ps1 -ProfilePath .\profiles\Smart11MTN-nl.ovpn
```

WireGuard example:

```bash
./scripts/start-stack.sh --profile-path ./profiles/VS7.conf
```

The script will:

1. Apply the profile (WireGuard or OpenVPN, detected by `.conf` / `.ovpn`)
2. Ensure a VLESS UUID exists in `xray/config.json`
3. Start `gluetun` + `xray` with Docker Compose
4. Wait until the VPN tunnel is up
5. Print **two VLESS links** in bordered, colored blocks (cyan = LAN, green = localhost; English console output):
   - **LAN** — host IP of this machine on Wi‑Fi (`get-lan-ip`); paste into v2rayNG / NekoBox on your **phone or another device** on the same network
   - **127.0.0.1** — for testing in a client on **this PC only**

Set `NO_COLOR=1` to disable ANSI colors in Bash (borders remain).

Optional: `--host <ip>` / `-HostAddr <ip>` overrides the detected LAN IP in the first link (e.g. if auto-detection picks the wrong adapter).

**Recommended:** use `start-stack` for normal use — one profile path, Docker starts, VLESS link is printed. That is enough for most people.

**Manual mode:** the steps below (Step 1 → Step 4) run the same workflow **one command at a time** (`switch-*-profile`, `generate-secrets`, `docker compose up`, `print-vless-uri`). Use manual mode when you want to inspect or change something between steps (e.g. edit `.env` after switching profile, regenerate UUID only, restart Docker without re-applying the profile). You do **not** need manual mode if `start-stack` works for you.

---

## Manual setup (step by step)

Skip this section if you already used **Quick start** and the stack is running.

## Step 1 — `.env` file

Compose, `print-vless-uri`, and Gluetun all expect a **`.env`** in the repo root. Nothing in the repo commits a real `.env`; you start from **`.env.example`**.

**Option A — create it yourself** (from the repo root):

```bash
cp .env.example .env
```

```powershell
Copy-Item .env.example .env
```

**Option B — skip this step for now:** in **Step 3**, `switch-wireguard-profile` or `switch-openvpn-profile` will **create `.env` automatically** by copying `.env.example` if `.env` is missing, then set the VPN-related variables for that profile type.

So the manual `cp` is optional when you use either switch script with the default `.env` path.

### `.env` variables by VPN type

| Variable | WireGuard (`VPN_TYPE=wireguard`) | OpenVPN (`VPN_TYPE=openvpn`) |
|----------|----------------------------------|------------------------------|
| `VPN_TYPE` | `wireguard` | `openvpn` |
| `WG_PRIVATE_KEY`, `WG_ADDRESSES`, `WG_PUBLIC_KEY`, `WG_ENDPOINT_IP`, `WG_ENDPOINT_PORT`, `WG_PRESHARED_KEY` | Required (filled by `switch-wireguard-profile`) | Ignored |
| `OVPN_USER`, `OVPN_PASSWORD` | Ignored | Required if your `.ovpn` contains `auth-user-pass` (panel username/password) |

Gluetun reads the OpenVPN file from `gluetun/custom.ovpn` (see `OPENVPN_CUSTOM_CONFIG` in `docker-compose.yml`). The `gluetun/` folder is gitignored because it contains certificates and keys.

---

## Step 2 — Put VPN profiles in `profiles/`

Copy your provider’s config files into the `profiles/` folder (this folder is gitignored). Use one file per server/location you want to switch between.

**WireGuard** (`.conf`), for example:

- `profiles/VS7.conf`
- `profiles/IR.conf`

**OpenVPN** (`.ovpn`), for example:

- `profiles/Smart11MTN-nl.ovpn`

Most `.ovpn` exports already embed `<ca>`, `<cert>`, `<key>`, and `<tls-auth>`. If yours only has `auth-user-pass` without inline certs, you still need valid `OVPN_USER` / `OVPN_PASSWORD` from the provider panel.

---

## Step 3 — Apply a profile, set UUID, start Docker

Same stages as `start-stack`, but split into separate commands. Still from the repo root; pick **either** WireGuard (3a) **or** OpenVPN (3b) — not both at once.

### 3a — WireGuard: push profile values into `.env`

Reads `PrivateKey`, `Address`, `PublicKey`, `Endpoint`, resolves the endpoint hostname to IPv4 when needed, sets `VPN_TYPE=wireguard`, and writes `WG_*`:

```bash
./scripts/switch-wireguard-profile.sh --profile-path ./profiles/VS7.conf --restart-stack
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\switch-wireguard-profile.ps1 -ProfilePath .\profiles\VS7.conf -RestartStack
```

### 3b — OpenVPN: install profile and set `VPN_TYPE=openvpn`

Copies your `.ovpn` to `gluetun/custom.ovpn`, **resolves any `remote` hostname to IPv4** (Gluetun does not allow domain names there), and sets `VPN_TYPE=openvpn` in `.env`:

```bash
./scripts/switch-openvpn-profile.sh --profile-path ./profiles/Smart11MTN-nl.ovpn
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\switch-openvpn-profile.ps1 -ProfilePath .\profiles\Smart11MTN-nl.ovpn
```

Then edit `.env` and set credentials when the profile uses `auth-user-pass`:

```env
OVPN_USER=your_panel_username
OVPN_PASSWORD=your_panel_password
```

To switch to another OpenVPN server later, run the same script with a different `--profile-path` / `-ProfilePath`.

**Restart flag:** use `--restart-stack` / `-RestartStack` only if the stack is **already** running and you want to recreate `gluetun` and `xray`. For the first start you can omit it.

**Manual OpenVPN (without the script):**

1. `cp .env.example .env` and set `VPN_TYPE=openvpn`.
2. `mkdir -p gluetun` and copy your file to `gluetun/custom.ovpn`.
3. In `custom.ovpn`, change `remote hostname 110` to `remote 1.2.3.4 110` (use `nslookup hostname` on your PC). Gluetun rejects hostnames in `remote` lines to avoid DNS leaks before the tunnel is up.
4. Set `OVPN_USER` and `OVPN_PASSWORD` in `.env` if required.

If the server’s IP changes later, re-run `switch-openvpn-profile` or update the `remote` line again.

### 3c — Generate a new VLESS UUID

Writes a new id into `xray/config.json` for all clients that use an `id`:

```bash
./scripts/generate-secrets.sh
```

```powershell
.\scripts\generate-secrets.ps1
```

### 3d — Start the stack

```bash
docker compose up -d
```

Optional: watch logs

```bash
docker compose logs -f gluetun
docker compose logs -f xray
```

**Check upstream VPN (OpenVPN or WireGuard):** Gluetun should log a successful tunnel; then verify egress from the container path, e.g. [https://ipinfo.io/ip](https://ipinfo.io/ip) on a client using Xray.

---

## Step 4 — VLESS share link (copy into NekoBox / v2rayNG / v2rayN)

The server listens on the host mapped port (default `XRAY_PORT=28443` in `.env`). Build a standard **VLESS** URI for plain TCP on LAN (no TLS):

```bash
./scripts/print-vless-uri.sh --host 127.0.0.1
```

```powershell
.\scripts\print-vless-uri.ps1 -HostAddr 127.0.0.1
# or (same): .\scripts\print-vless-uri.ps1 --host 127.0.0.1
```

By default the host in the link is your LAN IP (via `get-lan-ip`). Override if needed:

```bash
./scripts/print-vless-uri.sh --host 192.168.1.10 --remark "home-lan"
```

```powershell
.\scripts\print-vless-uri.ps1 -HostAddr 192.168.1.10 -Remark "home-lan"
```

Copy the printed `vless://...` line. In the client, use **import from clipboard** / **import URI** (wording varies by app).

### Client downloads

- **NekoBox (Android):** [https://github.com/MatsuriDayo/NekoBoxForAndroid](https://github.com/MatsuriDayo/NekoBoxForAndroid)
- **v2rayNG (Android):** [https://github.com/2dust/v2rayNG](https://github.com/2dust/v2rayNG)
- **v2rayN (Windows):** [https://github.com/2dust/v2rayN](https://github.com/2dust/v2rayN)

After connecting, check egress e.g. [https://ipinfo.io/ip](https://ipinfo.io/ip) — it should match the VPN upstream seen from Gluetun.

---

## Firewall (host)

**Windows (CMD as admin, no PowerShell):**

```bat
netsh advfirewall firewall add rule name="Xray LAN 28443" dir=in action=allow protocol=TCP localport=28443
```

Adjust `localport` if you changed `XRAY_PORT`.

**Linux (UFW example):**

```bash
sudo ufw allow 28443/tcp
```

---

## Optional helper scripts

| Script | Purpose |
|--------|--------|
| `start-stack.sh` / `.ps1` | **All-in-one:** apply profile, start Docker, wait for VPN, print VLESS URI |
| `get-lan-ip.sh` / `.ps1` | Print a likely LAN IPv4 |
| `switch-wireguard-profile.*` | Fill `WG_*` in `.env` from a `.conf` |
| `switch-openvpn-profile.*` | Copy `.ovpn` to `gluetun/custom.ovpn`, set `VPN_TYPE=openvpn` |
| `generate-secrets.*` | New UUID in `xray/config.json` |
| `print-vless-uri.*` | Print `vless://` URI for clients |

---

## Routing in `xray/config.json`

- Ads blocked via `geosite:category-ads-all`.
- `private` geo goes direct.
- Default outbound is `freedom` (traffic follows the container/VPN path).

---

## Notes

- This layout is aimed at **trusted LAN**; there is no public TLS / REALITY on the inbound.
- On Windows, Docker does not offer Linux-style host networking; published ports + Gluetun is the expected pattern.
