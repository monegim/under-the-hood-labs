#!/usr/bin/env bash
# Lab 9 (InnoDB Redo Log Full) check — verifies the redo log capacity has
# actually been increased AND that any in-progress resize has completed.
set -uo pipefail

PRIMARY="lab09-primary"
MIN_CAPACITY=$((100*1024*1024))  # require at least 100MB configured

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying primary container is running..."
status=$(docker inspect -f '{{.State.Running}}' "$PRIMARY" 2>/dev/null)
[ "$status" = "true" ] || fail "container $PRIMARY is not running (run setup.sh first)"

echo "[check] reading innodb_redo_log_capacity..."
CAPACITY=$(docker exec "$PRIMARY" mysql -uroot -prootpass -N -e \
  "SHOW VARIABLES LIKE 'innodb_redo_log_capacity';" 2>/dev/null | awk '{print $2}')
[ -n "$CAPACITY" ] || fail "could not read innodb_redo_log_capacity"

echo "[check] innodb_redo_log_capacity=$CAPACITY (need >= $MIN_CAPACITY)"
if [ "$CAPACITY" -lt "$MIN_CAPACITY" ]; then
  fail "innodb_redo_log_capacity is still too small ($CAPACITY bytes)"
fi

echo "[check] verifying no resize is currently in progress..."
RESIZE=$(docker exec "$PRIMARY" mysql -uroot -prootpass -N -e \
  "SHOW GLOBAL STATUS LIKE 'Innodb_redo_log_resize_status';" 2>/dev/null | awk '{print $2}')
if [ -n "$RESIZE" ]; then
  fail "a redo log resize is still in progress ('$RESIZE') — wait for it to finish"
fi

echo "[PASS] innodb_redo_log_capacity=$CAPACITY bytes, no resize in progress"
exit 0
