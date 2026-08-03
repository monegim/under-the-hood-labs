#!/usr/bin/env bash
# Lab 33 (Autovacuum Disabled) check — verifies autovacuum is re-enabled
# for the accounts table AND that dead tuples have actually been cleaned
# up (re-enabling autovacuum alone doesn't retroactively vacuum anything).
set -uo pipefail

PRIMARY="lab33-primary"
MAX_DEAD_TUP=100

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying primary container is running..."
status=$(docker inspect -f '{{.State.Running}}' "$PRIMARY" 2>/dev/null)
[ "$status" = "true" ] || fail "container $PRIMARY is not running (run setup.sh first)"

echo "[check] checking accounts' autovacuum_enabled reloption..."
RELOPTS=$(docker exec "$PRIMARY" psql -U postgres -d appdb -tAc \
  "SELECT COALESCE(array_to_string(reloptions, ','), '') FROM pg_class WHERE relname = 'accounts';" 2>/dev/null)
if echo "$RELOPTS" | grep -q "autovacuum_enabled=false"; then
  fail "accounts still has autovacuum_enabled=false set (reloptions: $RELOPTS)"
fi

echo "[check] checking dead tuple count..."
DEAD=$(docker exec "$PRIMARY" psql -U postgres -d appdb -tAc \
  "SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'accounts';" 2>/dev/null | tr -d ' ')
[ -n "$DEAD" ] || fail "could not read n_dead_tup for accounts (does the table exist?)"

echo "[check] n_dead_tup=$DEAD"
if [ "$DEAD" -gt "$MAX_DEAD_TUP" ]; then
  fail "n_dead_tup is $DEAD (> $MAX_DEAD_TUP) — accounts still needs a VACUUM"
fi

echo "[PASS] autovacuum_enabled is not disabled, and n_dead_tup=$DEAD (<= $MAX_DEAD_TUP)"
exit 0
