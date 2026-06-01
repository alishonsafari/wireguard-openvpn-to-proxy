param(
  [Parameter(Mandatory = $true)]
  [string]$ProfilePath,
  [string]$HostAddr = "",
  [string]$Remark = "gluetun-lan",
  [string]$EnvPath = ".\.env",
  [int]$TimeoutSec = 120
)

$ErrorActionPreference = "Stop"

function Write-Log([string]$Message) { Write-Host $Message }
function Write-Ok([string]$Message) { Write-Host "[OK] $Message" }
function Write-Info([string]$Message) { Write-Host "[..] $Message" }
function Write-Fail([string]$Message) {
  Write-Host "[ERROR] $Message"
  exit 1
}

function Write-VlessBox {
  param(
    [string]$Title,
    [string]$Uri,
    [string]$Hint = "Paste into v2rayN / v2rayNG / NekoBox -> Import from clipboard",
    [ConsoleColor]$UriColor = "Cyan"
  )
  $w = [Math]::Max($Uri.Length, $Title.Length) + 4
  $bar = ("─" * $w)
  Write-Host ""
  Write-Host $bar -ForegroundColor DarkGray
  Write-Host "  $Title" -ForegroundColor White
  Write-Host "  $Hint" -ForegroundColor DarkGray
  Write-Host "  $Uri" -ForegroundColor $UriColor
  Write-Host $bar -ForegroundColor DarkGray
  Write-Host ""
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path

if (-not (Test-Path -LiteralPath $ProfilePath)) {
  $candidate = Join-Path $RepoRoot ($ProfilePath -replace '^\./', '')
  if (Test-Path -LiteralPath $candidate) {
    $ProfilePath = $candidate
  } else {
    Write-Fail "Profile file not found: $ProfilePath"
  }
} else {
  $ProfilePath = (Resolve-Path -LiteralPath $ProfilePath).Path
}

if (-not (Test-Path -LiteralPath $EnvPath)) {
  $envCandidate = Join-Path $RepoRoot ($EnvPath -replace '^\./', '')
  if (Test-Path -LiteralPath $envCandidate) { $EnvPath = $envCandidate }
} else {
  $EnvPath = (Resolve-Path -LiteralPath $EnvPath).Path
}

try {
  docker compose version | Out-Null
} catch {
  Write-Fail "Docker or docker compose is not available."
}

$ext = [System.IO.Path]::GetExtension($ProfilePath).ToLowerInvariant()
Set-Location $RepoRoot

Write-Info "Applying VPN profile: $ProfilePath"
switch ($ext) {
  ".ovpn" {
    & (Join-Path $ScriptDir "switch-openvpn-profile.ps1") -ProfilePath $ProfilePath -EnvPath $EnvPath
  }
  ".conf" {
    & (Join-Path $ScriptDir "switch-wireguard-profile.ps1") -ProfilePath $ProfilePath -EnvPath $EnvPath
  }
  default {
    Write-Fail "Unsupported profile extension: $ext (use .ovpn or .conf only)"
  }
}
Write-Ok "VPN profile applied to .env and gluetun."

if ($ext -eq ".ovpn") {
  $customOvpn = Join-Path $RepoRoot "gluetun\custom.ovpn"
  if ((Test-Path $customOvpn) -and (Select-String -Path $customOvpn -Pattern '^\s*auth-user-pass' -Quiet)) {
    $envLines = Get-Content -Path $EnvPath
    $hasUser = $envLines | Where-Object { $_ -match '^\s*OVPN_USER=.+' }
    $hasPass = $envLines | Where-Object { $_ -match '^\s*OVPN_PASSWORD=.+' }
    if (-not $hasUser -or -not $hasPass) {
      Write-Fail "This OpenVPN profile requires auth-user-pass. Set OVPN_USER and OVPN_PASSWORD in .env."
    }
  }
  Write-Ok "OpenVPN credentials (OVPN_USER / OVPN_PASSWORD) are set in .env."
}

$configPath = Join-Path $RepoRoot "xray\config.json"
$hasUuid = $false
if (Test-Path $configPath) {
  $cfg = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($ib in $cfg.inbounds) {
    if ($ib.protocol -eq "vless" -and $ib.settings.clients -and $ib.settings.clients[0].id) {
      $hasUuid = $true
      break
    }
  }
}

if (-not $hasUuid) {
  Write-Info "No VLESS UUID in xray/config.json; generating..."
  & (Join-Path $ScriptDir "generate-secrets.ps1")
  Write-Ok "UUID written to xray/config.json."
} else {
  Write-Ok "VLESS client UUID found in xray/config.json."
}

Write-Info "Starting Docker (gluetun + xray)..."
docker compose up -d --force-recreate gluetun xray

Write-Info "Waiting for VPN connection (up to $TimeoutSec s)..."
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$vpnOk = $false
while ((Get-Date) -lt $deadline) {
  $logs = docker compose logs gluetun 2>&1 | Out-String
  if ($logs -match "Initialization Sequence Completed") {
    $vpnOk = $true
    break
  }
  if ($logs -match "ERROR VPN settings" -or $logs -match "Shutdown successful") {
    break
  }
  $running = docker inspect -f '{{.State.Running}}' vpn-upstream 2>$null
  if ($running -ne "true") {
    Start-Sleep -Seconds 2
    $running = docker inspect -f '{{.State.Running}}' vpn-upstream 2>$null
    if ($running -ne "true") { break }
  }
  Start-Sleep -Seconds 2
}

if (-not $vpnOk) {
  $tail = docker compose logs gluetun --tail 25 2>&1 | Out-String
  Write-Fail "VPN did not come up. Last gluetun logs:`n$tail"
}
Write-Ok "VPN tunnel (gluetun) is up."

$xrayRunning = docker inspect -f '{{.State.Running}}' xray-lan-gateway 2>$null
if ($xrayRunning -ne "true") {
  $xtail = docker compose logs xray --tail 15 2>&1 | Out-String
  Write-Fail "xray container is not running. Logs:`n$xtail"
}
Write-Ok "Xray is running."

$lanIp = $HostAddr
if (-not $lanIp) {
  try {
    $lanIp = & (Join-Path $ScriptDir "get-lan-ip.ps1")
  } catch {
    $lanIp = $null
  }
}

$vlessLan = $null
if ($lanIp) {
  $vlessLan = & (Join-Path $ScriptDir "print-vless-uri.ps1") -HostAddr $lanIp -Remark "$Remark-lan"
} else {
  Write-Info "Could not detect LAN IP; only the localhost VLESS link is shown."
}

$vlessLocal = & (Join-Path $ScriptDir "print-vless-uri.ps1") -HostAddr 127.0.0.1 -Remark "$Remark-local"

Write-Log ""
Write-Log "========================================"
Write-Ok "All checks passed — stack is ready."
Write-Log "========================================"
Write-Log ""
if ($vlessLan) {
  Write-VlessBox `
    -Title "VLESS — phone / other devices on Wi-Fi (host $lanIp)" `
    -Uri $vlessLan `
    -UriColor Cyan
}
Write-VlessBox `
  -Title "VLESS — this PC only (127.0.0.1)" `
  -Uri $vlessLocal `
  -UriColor Green
Write-Log "Xray port is from .env (default 28443). Traffic exits through the VPN upstream."
Write-Log "Optional: after connecting a client, check egress IP at https://ipinfo.io/ip"
Write-Log "========================================"
