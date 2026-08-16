#!/usr/bin/env bash
# Lab 07 check — verifies age(relfrozenxid) for the counters table is
# back under the (lowered, for this lab) autovacuum_freeze_max_age
# threshold, i.e. a real freeze actually happened.
set -uo pipefail

PRIMARY="pglab7-primary"
THRESHOLD=100000

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying primary container is running..."
status=$(docker inspect -f '{{.State.Running}}' "$PRIMARY" 2>/dev/null)
[ "$status" = "true" ] || fail "container $PRIMARY is not running (run setup.sh first)"

echo "[check] current age(relfrozenxid) for counters..."
AGE=$(docker exec "$PRIMARY" psql -U postgres -d appdb -tAc \
  "SELECT age(relfrozenxid) FROM pg_class WHERE relname = 'counters';" 2>/dev/null | tr -d ' ')
[ -n "$AGE" ] || fail "could not query age(relfrozenxid) for counters"
echo "[check] age(relfrozenxid) = $AGE (threshold: $THRESHOLD)"

if [ "$AGE" -ge "$THRESHOLD" ]; then
    fail "age($AGE) is still at or above the freeze_max_age threshold ($THRESHOLD) — not resolved."
fi

echo "[PASS] age(relfrozenxid) is back under the threshold — the table was actually frozen."
exit 0
