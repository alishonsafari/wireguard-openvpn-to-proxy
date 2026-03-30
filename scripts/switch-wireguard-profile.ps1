param(
  [Parameter(Mandatory = $true)]
  [string]$ProfilePath,
  [string]$EnvPath = ".\.env",
  [switch]$RestartStack
)

if (-not (Test-Path $ProfilePath)) {
  throw "WireGuard profile not found: $ProfilePath"
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
$profileText = Get-Content -Path $profileFullPath -Raw

function Get-IniValue {
  param(
    [string]$Text,
    [string]$Key
  )
  $m = [regex]::Match($Text, "(?im)^\s*$Key\s*=\s*(.+?)\s*$")
  if ($m.Success) { return $m.Groups[1].Value.Trim() }
  return $null
}

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

$privateKey = Get-IniValue -Text $profileText -Key "PrivateKey"
$address = Get-IniValue -Text $profileText -Key "Address"
$publicKey = Get-IniValue -Text $profileText -Key "PublicKey"
$endpoint = Get-IniValue -Text $profileText -Key "Endpoint"

if (-not $privateKey -or -not $address -or -not $publicKey -or -not $endpoint) {
  throw "Profile is missing one of required keys: PrivateKey, Address, PublicKey, Endpoint"
}

$endpointParts = $endpoint.Split(":")
if ($endpointParts.Count -lt 2) {
  throw "Endpoint format is invalid: $endpoint"
}

$endpointHost = $endpointParts[0]
$endpointPort = $endpointParts[$endpointParts.Count - 1]

$endpointIp = $endpointHost
$parsedIp = $null
$isIp = [System.Net.IPAddress]::TryParse($endpointHost, [ref]$parsedIp)
if (-not $isIp) {
  try {
    $resolved = Resolve-DnsName -Name $endpointHost -Type A -ErrorAction Stop | Select-Object -First 1 -ExpandProperty IPAddress
    if (-not $resolved) { throw "No A record found" }
    $endpointIp = $resolved
  } catch {
    throw "Failed to resolve endpoint host '$endpointHost' to IPv4: $($_.Exception.Message)"
  }
}

$envText = Get-Content -Path $envFullPath -Raw
$envText = Set-EnvValue -Text $envText -Key "VPN_TYPE" -Value "wireguard"
$envText = Set-EnvValue -Text $envText -Key "WG_PRIVATE_KEY" -Value $privateKey
$envText = Set-EnvValue -Text $envText -Key "WG_ADDRESSES" -Value $address
$envText = Set-EnvValue -Text $envText -Key "WG_PUBLIC_KEY" -Value $publicKey
$envText = Set-EnvValue -Text $envText -Key "WG_ENDPOINT_IP" -Value $endpointIp
$envText = Set-EnvValue -Text $envText -Key "WG_ENDPOINT_PORT" -Value $endpointPort

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($envFullPath, $envText, $utf8NoBom)

Write-Host "Switched profile from: $profileFullPath"
Write-Host "WG_ENDPOINT_IP: $endpointIp"
Write-Host "WG_ENDPOINT_PORT: $endpointPort"

if ($RestartStack) {
  Write-Host "Restarting Docker stack..."
  docker compose up -d --force-recreate gluetun xray
  docker compose ps
}
