$cfg = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1
if ($cfg) { $cfg.IPv4Address.IPAddress } else {
  (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -match '^192\.168\.|^10\.' } | Select-Object -First 1).IPAddress
}
