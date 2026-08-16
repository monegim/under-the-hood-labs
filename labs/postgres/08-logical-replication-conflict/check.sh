#!/usr/bin/env bash
# Lab 08 check — verifies the subscriber has fully caught up with the
# publisher: the conflicting row resolved to the publisher's data (not
# silently kept the subscriber's stale local value) and the row inserted
# after the conflict made it through too.
set -uo pipefail

PUBLISHER="pglab8-publisher"
SUBSCRIBER="pglab8-subscriber"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying both containers are running..."
for c in "$PUBLISHER" "$SUBSCRIBER"; do
  running=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
  [ "$running" = "true" ] || fail "container $c is not running (run setup.sh first)"
done

echo "[check] comparing orders on publisher vs subscriber..."
PUB_ROWS=$(docker exec "$PUBLISHER" psql -U postgres -d appdb -tAc \
  "SELECT id || ':' || item FROM orders ORDER BY id;" 2>/dev/null)
SUB_ROWS=$(docker exec "$SUBSCRIBER" psql -U postgres -d appdb -tAc \
  "SELECT id || ':' || item FROM orders ORDER BY id;" 2>/dev/null)

echo "[check] publisher: $PUB_ROWS"
echo "[check] subscriber: $SUB_ROWS"

[ -n "$PUB_ROWS" ] || fail "could not read orders from publisher"
[ "$PUB_ROWS" = "$SUB_ROWS" ] || fail "subscriber has not caught up with publisher (still diverged or missing rows)"

echo "[check] confirming the replication worker is actually running (not crash-looping)..."
PID=$(docker exec "$SUBSCRIBER" psql -U postgres -d appdb -tAc \
  "SELECT pid FROM pg_stat_subscription WHERE subname = 'orders_sub';" 2>/dev/null | tr -d ' ')
[ -n "$PID" ] || fail "pg_stat_subscription shows no active worker pid for orders_sub"

echo "[PASS] subscriber matches publisher and the replication worker is active."
exit 0
