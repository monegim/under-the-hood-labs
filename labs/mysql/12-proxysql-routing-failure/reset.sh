#!/usr/bin/env bash
# Lab 12 reset — tear the whole stack down, wipe the bind-mounted MySQL
# datadirs (docker compose down -v does NOT remove these, since they're
# host bind mounts, not named volumes — a known gotcha flagged elsewhere
# in this repo), then rebuild via setup.sh so the hostgroup-swap fault
# is reliably reintroduced from a clean slate.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[reset] tearing down the stack..."
docker compose down -v 2>/dev/null || true

echo "[reset] wiping bind-mounted data directories for a truly clean slate..."
rm -rf ./data

echo "[reset] rebuilding via setup.sh..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
