#!/usr/bin/env bash
# Lab 32 (WAL Full) check — verifies no inactive replication slot is still
# pinning WAL, and that the bounded WAL disk has headroom again.
set -uo pipefail

PRIMARY="lab32-primary"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WAL_DISK_MNT="$SCRIPT_DIR/data/wal-disk"
MAX_USE_PCT=80

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying primary container is running..."
status=$(docker inspect -f '{{.State.Running}}' "$PRIMARY" 2>/dev/null)
[ "$status" = "true" ] || fail "container $PRIMARY is not running (run setup.sh first)"

echo "[check] verifying primary accepts connections..."
docker exec "$PRIMARY" psql -U postgres -c "SELECT 1;" >/dev/null 2>&1 || fail "primary is not accepting connections"

echo "[check] checking for inactive replication slots still pinning WAL..."
STUCK=$(docker exec "$PRIMARY" psql -U postgres -tAc \
  "SELECT count(*) FROM pg_replication_slots WHERE active = false;" 2>/dev/null | tr -d ' ')
[ -n "$STUCK" ] || fail "could not query pg_replication_slots"
if [ "$STUCK" -gt 0 ]; then
  docker exec "$PRIMARY" psql -U postgres -c "SELECT slot_name, slot_type, active, wal_status FROM pg_replication_slots;"
  fail "$STUCK inactive replication slot(s) still exist — still pinning WAL, drop them"
fi

echo "[check] checking WAL disk usage..."
if mountpoint -q "$WAL_DISK_MNT" 2>/dev/null; then
  USE_PCT=$(df -P "$WAL_DISK_MNT" | awk 'NR==2 {gsub("%","",$5); print $5}')
else
  USE_PCT=$(docker exec "$PRIMARY" df -P /pgwal | awk 'NR==2 {gsub("%","",$5); print $5}')
fi
echo "[check] WAL disk usage: ${USE_PCT}%"
[ -n "$USE_PCT" ] || fail "could not read WAL disk usage"

if [ "$USE_PCT" -gt "$MAX_USE_PCT" ]; then
  fail "WAL disk usage is ${USE_PCT}% (> ${MAX_USE_PCT}%) — still nearly full"
fi

echo "[PASS] no inactive slots pinning WAL, WAL disk usage ${USE_PCT}% (<= ${MAX_USE_PCT}%), primary accepting connections"
exit 0
