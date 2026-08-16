#!/usr/bin/env bash
# Lab 13 check — verifies no long-running transaction is currently
# blocking purge, and that History List Length has actually come back
# down (not just that the blocker is gone — purge runs in the
# background and can take up to roughly a minute to catch up after a
# large backlog clears, so this polls rather than checking once).
set -uo pipefail

PRIMARY="lab13-primary"
THRESHOLD=200
TIMEOUT_SECONDS=90

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying primary container is running..."
status=$(docker inspect -f '{{.State.Running}}' "$PRIMARY" 2>/dev/null)
[ "$status" = "true" ] || fail "container $PRIMARY is not running (run setup.sh first)"

echo "[check] checking for any currently open transaction..."
OPEN_TRX=$(docker exec "$PRIMARY" mysql -uroot -prootpass -N -e \
  "SELECT COUNT(*) FROM information_schema.innodb_trx;" 2>/dev/null)
if [ "${OPEN_TRX:-0}" -gt 0 ]; then
    fail "$OPEN_TRX open transaction(s) still present — find and end them first"
fi
echo "[check] no open transactions."

echo "[check] waiting for History List Length to drop below $THRESHOLD (up to ${TIMEOUT_SECONDS}s — purge runs in the background, not instantly)..."
ELAPSED=0
while [ "$ELAPSED" -lt "$TIMEOUT_SECONDS" ]; do
    HLL=$(docker exec "$PRIMARY" mysql -uroot -prootpass -N -e "SHOW ENGINE INNODB STATUS\G" 2>/dev/null \
      | grep "History list length" | awk '{print $NF}')
    echo "[check] t=${ELAPSED}s History List Length=${HLL:-<unknown>}"
    if [ -n "$HLL" ] && [ "$HLL" -lt "$THRESHOLD" ] 2>/dev/null; then
        echo "[PASS] History List Length is back under $THRESHOLD (purge has caught up)."
        exit 0
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

fail "History List Length never dropped below $THRESHOLD within ${TIMEOUT_SECONDS}s"
