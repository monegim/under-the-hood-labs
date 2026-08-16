#!/usr/bin/env bash
# Incident 11 reset - tear down completely, wipe the shared disk state
# (both MySQL datadirs + reporting-job scratch files), and rebuild via
# setup.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[reset] tearing down existing containers..."
docker compose down 2>/dev/null || true

echo "[reset] wiping host disk state (primary + replica datadirs, reporting scratch)..."
rm -rf ./data

echo "[reset] re-running setup.sh to recreate the incident..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
