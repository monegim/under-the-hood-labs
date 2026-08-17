#!/usr/bin/env bash
# Lab 18 check — verifies the primary container is actually running (not
# crashed) and that all 125 rows are present and readable.
set -uo pipefail

PRIMARY="lab18-primary"
EXPECTED_ROWS=125

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying primary container is running (not crashed)..."
status=$(docker inspect -f '{{.State.Running}}' "$PRIMARY" 2>/dev/null)
[ "$status" = "true" ] || fail "container $PRIMARY is not running — it's likely crashed on the corrupted page (run setup.sh, then fix with FORCE_RECOVERY=1)"

echo "[check] querying orders..."
COUNT=$(docker exec "$PRIMARY" mysql -uroot -prootpass appdb -N -e "SELECT COUNT(*) FROM orders;" 2>/tmp/lab18-check-err)
if [ -z "$COUNT" ]; then
    fail "could not query orders: $(cat /tmp/lab18-check-err)"
fi

echo "[check] row count: $COUNT (expected: $EXPECTED_ROWS)"
[ "$COUNT" -eq "$EXPECTED_ROWS" ] || fail "expected $EXPECTED_ROWS rows, got $COUNT — data may still be missing"

echo "[PASS] primary is up and all $EXPECTED_ROWS rows are readable."
exit 0
