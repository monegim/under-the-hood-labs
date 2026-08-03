#!/usr/bin/env bash
# Incident 03 reset - tear down completely and rebuild via setup.sh, so
# auth's leaked file descriptors (which live inside its process, not on
# disk) are wiped along with the containers, and the incident is
# freshly reproduced.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[reset] tearing down existing containers..."
docker compose down 2>/dev/null || true

echo "[reset] re-running setup.sh to recreate the incident..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
