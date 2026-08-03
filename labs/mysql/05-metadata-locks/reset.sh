#!/usr/bin/env bash
# Lab 5 reset — kill any leftover background sessions from a previous run,
# drop the table, then re-run setup.sh to reproduce the MDL pileup.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] killing any leftover lab processes from a previous run..."
for f in /tmp/lab05-long-txn.pid /tmp/lab05-alter.pid /tmp/lab05-query-1.pid /tmp/lab05-query-2.pid /tmp/lab05-query-3.pid; do
  if [ -f "$f" ]; then
    kill -9 "$(cat "$f")" 2>/dev/null || true
    rm -f "$f"
  fi
done
rm -f /tmp/lab05-*.log

echo "[reset] killing any lingering MySQL sessions against appdb (fresh start)..."
mysql -uroot -prootpass -N -e "
  SELECT CONCAT('KILL ', id, ';') FROM information_schema.processlist WHERE db='appdb';
" 2>/dev/null | mysql -uroot -prootpass 2>/dev/null || true

echo "[reset] dropping orders table if present..."
mysql -uroot -prootpass appdb -e "DROP TABLE IF EXISTS orders;" 2>/dev/null || true

echo "[reset] re-running setup.sh to reproduce the incident..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
