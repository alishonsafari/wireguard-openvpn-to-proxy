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

python3 - "${CONFIG_PATH}" <<'PY'
import json, pathlib, sys, uuid

path = pathlib.Path(sys.argv[1])
raw = path.read_text(encoding="utf-8")
config = json.loads(raw)
new_uuid = str(uuid.uuid4())

for inbound in config.get("inbounds") or []:
    settings = inbound.get("settings") or {}
    clients = settings.get("clients")
    if not clients:
        continue
    for client in clients:
        if isinstance(client, dict) and "id" in client:
            client["id"] = new_uuid

path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
print("New UUID generated and saved:")
print(new_uuid)
PY
