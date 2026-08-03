#!/usr/bin/env bash
# Lab 3 reset — drop and reseed the accounts table, then re-run the
# concurrent opposite-order transfers to reproduce the deadlock.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] dropping accounts table if present..."
mysql -uroot -prootpass appdb -e "DROP TABLE IF EXISTS accounts;" 2>/dev/null || true

echo "[reset] re-running setup.sh to reseed and reproduce the deadlock..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
