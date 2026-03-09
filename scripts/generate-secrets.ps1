param(
  [string]$ConfigPath = ".\xray\config.json"
)

if (-not (Test-Path $ConfigPath)) {
  throw "Config file not found: $ConfigPath"
}

$resolvedPath = (Resolve-Path $ConfigPath).Path
$rawJson = Get-Content -Path $resolvedPath -Raw
$config = $rawJson | ConvertFrom-Json

$uuid = [guid]::NewGuid().ToString()
foreach ($inbound in $config.inbounds) {
  if ($inbound.settings -and $inbound.settings.clients) {
    foreach ($client in $inbound.settings.clients) {
      if ($client.PSObject.Properties.Name -contains "id") {
        $client.id = $uuid
      }
    }
  }
}

$updatedJson = $config | ConvertTo-Json -Depth 50
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($resolvedPath, $updatedJson, $utf8NoBom)

Write-Host "New UUID generated and saved:"
Write-Host $uuid
