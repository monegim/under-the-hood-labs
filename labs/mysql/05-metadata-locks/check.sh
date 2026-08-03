#!/usr/bin/env bash
# Lab 5 check — verifies nothing is currently stuck waiting for a metadata
# lock on 'orders' and the pending ALTER actually completed.
set -uo pipefail

fail() { echo "[FAIL] $1"; exit 1; }

if ! systemctl is-active --quiet mysql; then
    fail "mysql.service is not active"
fi

echo "[check] checking for any session waiting on a metadata lock..."
WAITERS=$(mysql -uroot -prootpass -N -e "
  SELECT COUNT(*) FROM information_schema.processlist
  WHERE state = 'Waiting for table metadata lock';
" 2>/dev/null)

if [ "${WAITERS:-0}" -gt 0 ]; then
    echo "[FAIL] $WAITERS session(s) still waiting on a metadata lock:"
    mysql -uroot -prootpass -e "
      SELECT id, user, time, state, LEFT(info,60) AS info
      FROM information_schema.processlist
      WHERE state = 'Waiting for table metadata lock';
    "
    exit 1
fi
echo "[check] no sessions currently waiting on a metadata lock."

echo "[check] confirming the ALTER TABLE actually completed (notes column exists)..."
COL_COUNT=$(mysql -uroot -prootpass appdb -N -e "
  SELECT COUNT(*) FROM information_schema.columns
  WHERE table_schema='appdb' AND table_name='orders' AND column_name='notes';
" 2>/dev/null)

[ "${COL_COUNT:-0}" -gt 0 ] || fail "orders.notes does not exist - the ALTER TABLE never completed"

echo "[check] orders.notes exists - ALTER TABLE completed."
echo "[PASS] no metadata-lock waiters and the pending ALTER finished."
exit 0
