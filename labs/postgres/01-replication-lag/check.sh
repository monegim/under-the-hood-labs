#!/usr/bin/env bash
# Lab 31 (Replication Lag) check — verifies streaming replication is
# currently healthy: standby is streaming, and replay is caught up with
# what's already been received (not just with what the primary has sent).
set -uo pipefail

PRIMARY="lab31-primary"
STANDBY="lab31-standby"
MAX_LAG_BYTES=$((16*1024*1024))  # 16MB of undrained WAL between receive and replay

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying primary and standby containers are running..."
for c in "$PRIMARY" "$STANDBY"; do
  status=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
  [ "$status" = "true" ] || fail "container $c is not running (run setup.sh first)"
done

echo "[check] querying pg_stat_replication on the primary..."
STATE=$(docker exec "$PRIMARY" psql -U postgres -tAc \
  "SELECT state FROM pg_stat_replication LIMIT 1;" 2>/dev/null | tr -d ' ')
[ "$STATE" = "streaming" ] || fail "standby is not in 'streaming' state on primary (got '$STATE')"

echo "[check] comparing receive LSN vs replay LSN on the standby..."
RECEIVE=$(docker exec "$STANDBY" psql -U postgres -tAc "SELECT pg_last_wal_receive_lsn();" 2>/dev/null | tr -d ' ')
REPLAY=$(docker exec "$STANDBY" psql -U postgres -tAc "SELECT pg_last_wal_replay_lsn();" 2>/dev/null | tr -d ' ')
[ -n "$RECEIVE" ] && [ -n "$REPLAY" ] || fail "could not read WAL receive/replay LSNs from standby"

DIFF=$(docker exec "$STANDBY" psql -U postgres -tAc \
  "SELECT pg_wal_lsn_diff('$RECEIVE', '$REPLAY');" 2>/dev/null | tr -d ' ' | cut -d. -f1)

echo "[check] receive_lsn=$RECEIVE replay_lsn=$REPLAY undrained_bytes=$DIFF"

[ -n "$DIFF" ] || fail "could not compute LSN diff"

if [ "$DIFF" -gt "$MAX_LAG_BYTES" ]; then
  fail "replay is ${DIFF} bytes behind receive (> ${MAX_LAG_BYTES}) — standby is still catching up"
fi

echo "[PASS] replication is healthy: streaming, replay within ${MAX_LAG_BYTES} bytes of received WAL"
exit 0
