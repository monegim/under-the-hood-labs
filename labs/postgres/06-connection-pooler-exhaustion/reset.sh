#!/usr/bin/env bash
# Lab 06 reset — tears the stack down, wipes the bind-mounted datadir
# (docker compose down -v doesn't remove host bind mounts), and rebuilds
# via setup.sh with default pool settings.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[reset] tearing down the stack..."
docker compose down -v 2>/dev/null || true

echo "[reset] wiping bind-mounted data directory..."
rm -rf ./data

echo "[reset] rebuilding via setup.sh (default pool_mode/pool_size)..."
unset POOL_MODE DEFAULT_POOL_SIZE
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
