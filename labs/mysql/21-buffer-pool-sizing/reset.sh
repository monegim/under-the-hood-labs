#!/usr/bin/env bash
# Lab 21 reset - tears down the stack, wipes the data directory (and
# any BUFFER_POOL_SIZE/OLD_BLOCKS_TIME override), and rebuilds via
# setup.sh with the default, undersized 24MB buffer pool.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[reset] tearing down the stack..."
unset BUFFER_POOL_SIZE OLD_BLOCKS_TIME
docker compose down -v 2>/dev/null || true

echo "[reset] wiping bind-mounted data directory..."
rm -rf ./data

echo "[reset] rebuilding via setup.sh..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
