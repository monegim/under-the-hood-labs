#!/usr/bin/env bash
# Lab 23 reset - tears down the stack, wipes the data directory, and
# rebuilds via setup.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[reset] tearing down the stack..."
docker compose down -v 2>/dev/null || true

echo "[reset] wiping bind-mounted data directory..."
rm -rf ./data

echo "[reset] rebuilding via setup.sh..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
