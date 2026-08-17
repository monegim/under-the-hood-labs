#!/usr/bin/env bash
# Incident 07 reset - tear down completely (including the tmpfs-backed
# shared_disk volume, so inode usage genuinely starts from zero again),
# and rebuild via setup.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[reset] tearing down existing containers and volumes..."
docker compose down -v 2>/dev/null || true

echo "[reset] re-running setup.sh to recreate the incident..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
