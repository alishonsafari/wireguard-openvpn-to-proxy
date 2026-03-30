param(
  [string]$HostAddr = "",
  [string]$Remark = "gluetun-lan",
  [string]$EnvPath = ".\.env",
  [string]$ConfigPath = ".\xray\config.json"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Resolve-Path (Join-Path $ScriptDir "..")
Push-Location $Root

try {
  if (-not (Test-Path $EnvPath)) {
    throw ".env not found. Create it first: Copy-Item .env.example .env"
  }
  if (-not (Test-Path $ConfigPath)) {
    throw "Config not found: $ConfigPath"
  }

  $xrayLine = Get-Content $EnvPath | Where-Object { $_ -match '^\s*XRAY_PORT=' } | Select-Object -First 1
  if (-not $xrayLine) { throw "XRAY_PORT missing in .env" }
  $XRAY_PORT = ($xrayLine -split '=', 2)[1].Trim()

  if (-not $HostAddr) {
    $HostAddr = & (Join-Path $ScriptDir "get-lan-ip.ps1")
    if (-not $HostAddr) {
      throw "Could not detect LAN IP. Pass -HostAddr 192.168.1.10"
    }
  }

  $raw = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
  $cfg = $raw | ConvertFrom-Json
  $uuid = $null
  foreach ($ib in $cfg.inbounds) {
    if ($ib.protocol -eq "vless" -and $ib.settings.clients) {
      $c0 = $ib.settings.clients[0]
      if ($c0.id) {
        $uuid = $c0.id
        break
      }
    }
  }
  if (-not $uuid) {
    throw "No VLESS client id in xray/config.json (run generate-secrets.ps1)."
  }

  $frag = [System.Uri]::EscapeDataString($Remark)
  $uri = "vless://${uuid}@${HostAddr}:${XRAY_PORT}?encryption=none&security=none&type=tcp&headerType=none#${frag}"
  Write-Output $uri
}
finally {
  Pop-Location
}
