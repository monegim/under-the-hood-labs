#!/usr/bin/env bash
# Lab 4 reset — drop the lab tables and slow log, then re-run setup.sh to
# regenerate the unindexed 500k-row products table.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] dropping products/seq_helper if present..."
mysql -uroot -prootpass appdb -e "DROP TABLE IF EXISTS products, seq_helper;" 2>/dev/null || true

echo "[reset] truncating the slow query log..."
sudo truncate -s 0 /var/log/mysql/mysql-slow.log 2>/dev/null || true

echo "[reset] re-running setup.sh to regenerate the incident..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
