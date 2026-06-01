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
  Write-Host "[خطا] $Message"
  exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path

if (-not (Test-Path -LiteralPath $ProfilePath)) {
  $candidate = Join-Path $RepoRoot ($ProfilePath -replace '^\./', '')
  if (Test-Path -LiteralPath $candidate) {
    $ProfilePath = $candidate
  } else {
    Write-Fail "فایل پروفایل پیدا نشد: $ProfilePath"
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
  Write-Fail "Docker یا docker compose در دسترس نیست."
}

$ext = [System.IO.Path]::GetExtension($ProfilePath).ToLowerInvariant()
Set-Location $RepoRoot

Write-Info "اعمال پروفایل VPN: $ProfilePath"
switch ($ext) {
  ".ovpn" {
    & (Join-Path $ScriptDir "switch-openvpn-profile.ps1") -ProfilePath $ProfilePath -EnvPath $EnvPath
  }
  ".conf" {
    & (Join-Path $ScriptDir "switch-wireguard-profile.ps1") -ProfilePath $ProfilePath -EnvPath $EnvPath
  }
  default {
    Write-Fail "پسوند پروفایل پشتیبانی نمی‌شود: $ext (فقط .ovpn یا .conf)"
  }
}
Write-Ok "پروفایل VPN روی .env و gluetun اعمال شد."

if ($ext -eq ".ovpn") {
  $customOvpn = Join-Path $RepoRoot "gluetun\custom.ovpn"
  if ((Test-Path $customOvpn) -and (Select-String -Path $customOvpn -Pattern '^\s*auth-user-pass' -Quiet)) {
    $envLines = Get-Content -Path $EnvPath
    $hasUser = $envLines | Where-Object { $_ -match '^\s*OVPN_USER=.+' }
    $hasPass = $envLines | Where-Object { $_ -match '^\s*OVPN_PASSWORD=.+' }
    if (-not $hasUser -or -not $hasPass) {
      Write-Fail "این پروفایل OpenVPN به auth-user-pass نیاز دارد. در .env مقدار OVPN_USER و OVPN_PASSWORD را پر کنید."
    }
  }
  Write-Ok "اعتبار OpenVPN (OVPN_USER / OVPN_PASSWORD) در .env تنظیم شده است."
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
  Write-Info "UUID در xray/config.json نیست؛ در حال ساخت..."
  & (Join-Path $ScriptDir "generate-secrets.ps1")
  Write-Ok "UUID ساخته و در xray/config.json ذخیره شد."
} else {
  Write-Ok "UUID کلاینت VLESS در xray/config.json موجود است."
}

Write-Info "بالا آوردن Docker (gluetun + xray)..."
docker compose up -d --force-recreate gluetun xray

Write-Info "منتظر اتصال VPN هستیم (حداکثر $TimeoutSec ثانیه)..."
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
  Write-Fail "VPN وصل نشد. آخرین لاگ gluetun:`n$tail"
}
Write-Ok "تونل VPN (gluetun) برقرار است."

$xrayRunning = docker inspect -f '{{.State.Running}}' xray-lan-gateway 2>$null
if ($xrayRunning -ne "true") {
  $xtail = docker compose logs xray --tail 15 2>&1 | Out-String
  Write-Fail "کانتینر xray در حال اجرا نیست. لاگ:`n$xtail"
}
Write-Ok "سرویس Xray در حال اجرا است."

$printArgs = @{ Remark = $Remark }
if ($HostAddr) { $printArgs.HostAddr = $HostAddr }
$vlessUri = & (Join-Path $ScriptDir "print-vless-uri.ps1") @printArgs

$lanIp = $null
try {
  if (-not $HostAddr) {
    $lanIp = & (Join-Path $ScriptDir "get-lan-ip.ps1")
  }
} catch { }

Write-Log ""
Write-Log "========================================"
Write-Ok "همه چیز درست است — استک آماده است."
Write-Log "========================================"
Write-Log ""
Write-Log "این لینک VLESS را در کلاینت (v2rayN / v2rayNG / NekoBox) کپی کنید:"
Write-Log "  Import from clipboard / وارد کردن از کلیپ‌بورد"
Write-Log ""
Write-Log $vlessUri
Write-Log ""
if ($lanIp -and -not $HostAddr) {
  Write-Log "آدرس LAN میزبان: $lanIp — کلاینت‌های دیگر روی همان Wi‑Fi باید به این IP وصل شوند."
} elseif ($HostAddr) {
  Write-Log "آدرس در لینک: $HostAddr (دستی تنظیم شده)"
}
Write-Log "پورت Xray از .env (معمولاً 28443). ترافیک از تونل VPN upstream خارج می‌شود."
Write-Log ""
Write-Log "بررسی اختیاری: بعد از اتصال کلاینت، IP خروجی را ببینید — https://ipinfo.io/ip"
Write-Log "========================================"
