#!/usr/bin/env bash
# Lab 06 check — verifies a fresh client connection through PgBouncer
# completes quickly (proving the pool isn't saturated/queuing anymore),
# and that PgBouncer's own pool stats show no one currently waiting.
set -uo pipefail

PGBOUNCER="pglab6-pgbouncer"
TIMEOUT_SECONDS=5

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying pgbouncer container is running..."
status=$(docker inspect -f '{{.State.Running}}' "$PGBOUNCER" 2>/dev/null)
[ "$status" = "true" ] || fail "container $PGBOUNCER is not running (run setup.sh first)"

echo "[check] attempting a fresh client connection through pgbouncer (timeout ${TIMEOUT_SECONDS}s)..."
if ! timeout "$TIMEOUT_SECONDS" docker exec -e PGPASSWORD=postgres "$PGBOUNCER" psql -h 127.0.0.1 -p 5432 -U postgres -d appdb -c "SELECT 1;" >/dev/null 2>&1; then
    fail "a fresh connection through pgbouncer did not complete within ${TIMEOUT_SECONDS}s — the pool is still saturated"
fi

echo "[check] checking pgbouncer's own pool stats for clients still waiting..."
POOLS=$(docker exec -e PGPASSWORD=postgres "$PGBOUNCER" psql -h 127.0.0.1 -p 5432 -U postgres -d pgbouncer -tA -c "SHOW POOLS;" 2>/dev/null)
echo "$POOLS"
WAITING=$(echo "$POOLS" | awk -F'|' '$1=="appdb" {print $4}')
if [ -n "$WAITING" ] && [ "$WAITING" -gt 0 ] 2>/dev/null; then
    fail "pgbouncer reports $WAITING client(s) still waiting for a pooled connection"
fi

echo "[PASS] fresh connections through pgbouncer succeed quickly, no clients waiting on the pool."
exit 0
