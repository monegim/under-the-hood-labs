#!/usr/bin/env bash
set -uo pipefail

# Lab 31 reset - tears the stack down completely and rebuilds via
# setup.sh, which rewrites haproxy.cfg fresh (undoing any fix edits).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[reset] tearing down..."
docker compose down 2>/dev/null || true

echo "[reset] re-running setup.sh..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
