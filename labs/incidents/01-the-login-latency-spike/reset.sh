#!/usr/bin/env bash
# Incident 01 reset - tear down the stack completely and rebuild via
# setup.sh, so the incident is freshly reproduced (any fix you applied
# by editing docker-compose.yml/app code is wiped, since setup.sh
# rebuilds images and recreates containers from scratch).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[reset] tearing down existing containers/volumes..."
docker compose down -v 2>/dev/null || true

echo "[reset] re-running setup.sh to recreate the incident..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
