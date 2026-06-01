param(
  [Parameter(Mandatory = $true)]
  [string]$ProfilePath,
  [string]$EnvPath = ".\.env",
  [switch]$RestartStack
)

if (-not (Test-Path $ProfilePath)) {
  throw "OpenVPN profile not found: $ProfilePath"
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path

if (-not (Test-Path -LiteralPath $EnvPath)) {
  $examplePath = Join-Path $RepoRoot ".env.example"
  if (-not (Test-Path $examplePath)) {
    throw ".env file not found: $EnvPath and no .env.example in repo to bootstrap from."
  }
  Copy-Item -LiteralPath $examplePath -Destination $EnvPath
  Write-Host "Created $EnvPath from .env.example"
}

$profileFullPath = (Resolve-Path $ProfilePath).Path
$envFullPath = (Resolve-Path $EnvPath).Path

function Resolve-Ipv4 {
  param([string]$HostName)
  $parsedIp = $null
  if ([System.Net.IPAddress]::TryParse($HostName, [ref]$parsedIp)) {
    return $parsedIp.ToString()
  }
  try {
    $resolved = Resolve-DnsName -Name $HostName -Type A -ErrorAction Stop |
      Select-Object -First 1 -ExpandProperty IPAddress
    if (-not $resolved) { throw "No A record found" }
    return $resolved
  } catch {
    throw "Failed to resolve OpenVPN remote host '$HostName' to IPv4: $($_.Exception.Message)"
  }
}

function Write-OpenVpnForGluetun {
  param(
    [string]$SourcePath,
    [string]$DestPath
  )
  $lines = Get-Content -Path $SourcePath
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($line in $lines) {
    # Match "remote <host> <port>" but not "remote-cert-tls" ($Host is read-only in PowerShell)
    if ($line -match '^\s*remote\s+(\S+)(\s+.*)?$' -and $line -notmatch '^\s*remote-') {
      $remoteHost = $Matches[1]
      $rest = $Matches[2]
      $ip = Resolve-Ipv4 -HostName $remoteHost
      if ($remoteHost -ne $ip) {
        Write-Host "Resolved remote ${remoteHost} -> ${ip}"
      }
      if ($rest -match '^\s+(\d+)') {
        $out.Add("remote $ip $($Matches[1])")
      } elseif ($rest) {
        $out.Add("remote $ip$rest")
      } else {
        $out.Add("remote $ip")
      }
    } else {
      $out.Add($line)
    }
  }
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllLines($DestPath, $out, $utf8NoBom)
}

$gluetunDir = Join-Path $RepoRoot "gluetun"
$customOvpn = Join-Path $gluetunDir "custom.ovpn"
New-Item -ItemType Directory -Force -Path $gluetunDir | Out-Null
Write-OpenVpnForGluetun -SourcePath $profileFullPath -DestPath $customOvpn

function Set-EnvValue {
  param(
    [string]$Text,
    [string]$Key,
    [string]$Value
  )
  $safeValue = if ($null -eq $Value) { "" } else { $Value }
  $pattern = "(?m)^$([regex]::Escape($Key))=.*$"
  if ([regex]::IsMatch($Text, $pattern)) {
    return [regex]::Replace($Text, $pattern, "$Key=$safeValue")
  }
  if ($Text.Length -gt 0 -and -not $Text.EndsWith("`n")) {
    $Text += "`r`n"
  }
  return $Text + "$Key=$safeValue`r`n"
}

$envText = Get-Content -Path $envFullPath -Raw
$envText = Set-EnvValue -Text $envText -Key "VPN_TYPE" -Value "openvpn"

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($envFullPath, $envText, $utf8NoBom)

Write-Host "Switched to OpenVPN profile: $profileFullPath"
Write-Host "Config copied to: $customOvpn"
Write-Host "VPN_TYPE=openvpn in $envFullPath"

$ovpnText = Get-Content -Path $customOvpn -Raw
if ($ovpnText -match '(?m)^auth-user-pass') {
  $envLines = Get-Content -Path $envFullPath
  $hasUser = $envLines | Where-Object { $_ -match '^OVPN_USER=.+' }
  $hasPass = $envLines | Where-Object { $_ -match '^OVPN_PASSWORD=.+' }
  if (-not $hasUser -or -not $hasPass) {
    Write-Warning "This profile uses auth-user-pass. Set OVPN_USER and OVPN_PASSWORD in $envFullPath before starting gluetun."
  }
}

if ($RestartStack) {
  Write-Host "Restarting Docker stack..."
  Set-Location $RepoRoot
  docker compose up -d --force-recreate gluetun xray
  docker compose ps
}
