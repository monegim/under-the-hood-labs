#!/usr/bin/env bash
# Incident 04 reset - tear down completely, wipe the shared disk state
# (MySQL datadir + backup-job scratch files), and rebuild via setup.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[reset] tearing down existing containers..."
docker compose down 2>/dev/null || true

echo "[reset] wiping host disk state (mysql datadir + backup scratch)..."
rm -rf ./data/disk

echo "[reset] re-running setup.sh to recreate the incident..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
