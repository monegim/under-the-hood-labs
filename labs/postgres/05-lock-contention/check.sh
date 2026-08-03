#!/usr/bin/env bash
# Lab 35 (Lock Contention) check — verifies nothing is idle in an open
# transaction, no session is currently blocked, and a real write against
# the contended row succeeds quickly.
set -uo pipefail

PRIMARY="lab35-primary"
TIMEOUT_SECONDS=5

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying primary container is running..."
status=$(docker inspect -f '{{.State.Running}}' "$PRIMARY" 2>/dev/null)
[ "$status" = "true" ] || fail "container $PRIMARY is not running (run setup.sh first)"

echo "[check] checking for idle-in-transaction sessions..."
IDLE=$(docker exec "$PRIMARY" psql -U postgres -tAc \
  "SELECT count(*) FROM pg_stat_activity WHERE state = 'idle in transaction';" 2>/dev/null | tr -d ' ')
[ -n "$IDLE" ] || fail "could not query pg_stat_activity"
if [ "$IDLE" -gt 0 ]; then
  docker exec "$PRIMARY" psql -U postgres -c \
    "SELECT pid, now() - xact_start AS xact_age, query FROM pg_stat_activity WHERE state = 'idle in transaction';"
  fail "$IDLE session(s) still idle in transaction — still holding locks"
fi

echo "[check] checking for any currently blocked session..."
BLOCKED=$(docker exec "$PRIMARY" psql -U postgres -tAc \
  "SELECT count(*) FROM pg_stat_activity WHERE cardinality(pg_blocking_pids(pid)) > 0;" 2>/dev/null | tr -d ' ')
[ -n "$BLOCKED" ] || fail "could not query pg_blocking_pids"
if [ "$BLOCKED" -gt 0 ]; then
  fail "$BLOCKED session(s) are currently blocked waiting on a lock"
fi

echo "[check] attempting a real write against the previously-contended row (timeout ${TIMEOUT_SECONDS}s)..."
if ! timeout "$TIMEOUT_SECONDS" docker exec "$PRIMARY" psql -U postgres -d appdb -c \
  "UPDATE accounts SET balance = balance + 0 WHERE id = 1;" >/dev/null 2>&1; then
  fail "write to accounts (id=1) did not complete within ${TIMEOUT_SECONDS}s — still contended"
fi

echo "[PASS] no idle-in-transaction sessions, no blocked sessions, and the row is writable again"
exit 0
