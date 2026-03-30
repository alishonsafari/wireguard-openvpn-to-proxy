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
- A WireGuard `.conf` (recommended) or OpenVPN profile.

Helper scripts exist in both **Bash** (`.sh`) and **PowerShell** (`.ps1`).

- **Bash:** Linux, macOS, Git Bash, WSL. From the repo root: `./scripts/...`. If needed: `chmod +x scripts/*.sh`
- **PowerShell:** Windows. If execution policy blocks scripts: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

---

## Step 1 — Create `.env`

From the **repository root** (where `docker-compose.yml` is):

```bash
cp .env.example .env
```

```powershell
Copy-Item .env.example .env
```

You can edit `.env` later (ports, `TZ`, and VPN fields). The next steps automate WireGuard fields when you use a profile file.

---

## Step 2 — Put WireGuard profiles in `profiles/`

Copy your provider’s WireGuard config files (`.conf`) into the `profiles/` folder, for example:

- `profiles/VS7.conf`
- `profiles/IR.conf`

Keep one file per location/server you want to switch between.

---

## Step 3 — Apply a profile, set UUID, start Docker

Still from the repo root.

**3a — Push profile values into `.env`** (reads `PrivateKey`, `Address`, `PublicKey`, `Endpoint`, resolves DNS if needed):

```bash
./scripts/switch-wireguard-profile.sh --profile-path ./profiles/VS7.conf --restart-stack
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\switch-wireguard-profile.ps1 -ProfilePath .\profiles\VS7.conf -RestartStack
```

Use `--restart-stack` / `-RestartStack` only if the stack is **already** running and you want to recreate `gluetun` and `xray`. For the first start you can omit it.

**3b — Generate a new VLESS UUID** (writes into `xray/config.json` for all clients that use an `id`):

```bash
./scripts/generate-secrets.sh
```

```powershell
.\scripts\generate-secrets.ps1
```

**3c — Start the stack**

```bash
docker compose up -d
```

Optional: watch logs

```bash
docker compose logs -f gluetun
docker compose logs -f xray
```

**OpenVPN:** set `VPN_TYPE=openvpn` in `.env`, place your file at `gluetun/custom.ovpn`, and fill any `OVPN_*` variables — no WireGuard profile step.

---

## Step 4 — VLESS share link (copy into NekoBox / v2rayNG / v2rayN)

The server listens on the host mapped port (default `XRAY_PORT=28443` in `.env`). Build a standard **VLESS** URI for plain TCP on LAN (no TLS):

```bash
./scripts/print-vless-uri.sh
```

```powershell
.\scripts\print-vless-uri.ps1
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
| `get-lan-ip.sh` / `.ps1` | Print a likely LAN IPv4 |
| `switch-wireguard-profile.*` | Fill `WG_*` in `.env` from a `.conf` |
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
