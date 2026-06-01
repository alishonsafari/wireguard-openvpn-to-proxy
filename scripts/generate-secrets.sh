#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_PATH="${1:-${REPO_ROOT}/xray/config.json}"

if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "Config file not found: ${CONFIG_PATH}" >&2
  exit 1
fi

CONFIG_PATH="$(cd "$(dirname "${CONFIG_PATH}")" && pwd)/$(basename "${CONFIG_PATH}")"

if ! command -v node >/dev/null 2>&1; then
  echo "node is required for generate-secrets.sh (no usable python3 detected)." >&2
  exit 1
fi

node - "${CONFIG_PATH}" <<'NODE'
const fs = require('fs');
const { randomUUID } = require('crypto');

const configPath = process.argv[2];
if (!fs.existsSync(configPath)) {
  console.error('Config file not found:', configPath);
  process.exit(1);
}

const raw = fs.readFileSync(configPath, 'utf8');
const config = JSON.parse(raw);

const newUuid = randomUUID();

for (const inbound of (config.inbounds || [])) {
  const settings = inbound?.settings || {};
  const clients = settings?.clients;
  if (!Array.isArray(clients)) continue;

  for (const client of clients) {
    if (client && typeof client === 'object' && Object.prototype.hasOwnProperty.call(client, 'id')) {
      client.id = newUuid;
    }
  }
}

fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n', 'utf8');
console.log('New UUID generated and saved:');
console.log(newUuid);
NODE
