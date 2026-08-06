#!/usr/bin/env bash
# Lab 10 (Semi-Sync Replication Timeout) check — verifies both containers
# are running/unpaused, replication threads are healthy, and semi-sync is
# currently ON (i.e. the primary is actually getting ACKs again, not just
# configured to want them).
set -uo pipefail

PRIMARY="lab10-primary"
REPLICA="lab10-replica"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying primary and replica containers are running and not paused..."
for c in "$PRIMARY" "$REPLICA"; do
  status=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
  [ "$status" = "true" ] || fail "container $c is not running (run setup.sh first)"
  paused=$(docker inspect -f '{{.State.Paused}}' "$c" 2>/dev/null)
  [ "$paused" = "false" ] || fail "container $c is paused (run: docker unpause $c)"
done

echo "[check] verifying replica threads are healthy..."
STATUS=$(docker exec "$REPLICA" mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" 2>/dev/null)
IO_RUNNING=$(echo "$STATUS" | awk -F': ' '/Replica_IO_Running:/{print $2; exit}')
SQL_RUNNING=$(echo "$STATUS" | awk -F': ' '/Replica_SQL_Running:/{print $2; exit}')
[ "$IO_RUNNING" = "Yes" ] || fail "Replica_IO_Running is not Yes (got '$IO_RUNNING')"
[ "$SQL_RUNNING" = "Yes" ] || fail "Replica_SQL_Running is not Yes (got '$SQL_RUNNING')"

echo "[check] verifying semi-sync is currently ON on the primary..."
SEMISYNC=$(docker exec "$PRIMARY" mysql -uroot -prootpass -N -e \
  "SHOW STATUS LIKE 'Rpl_semi_sync_source_status';" 2>/dev/null | awk '{print $2}')
[ "$SEMISYNC" = "ON" ] || fail "Rpl_semi_sync_source_status is '$SEMISYNC', expected ON"

echo "[check] verifying at least one semi-sync replica is attached..."
CLIENTS=$(docker exec "$PRIMARY" mysql -uroot -prootpass -N -e \
  "SHOW STATUS LIKE 'Rpl_semi_sync_source_clients';" 2>/dev/null | awk '{print $2}')
[ -n "$CLIENTS" ] && [ "$CLIENTS" -ge 1 ] || fail "Rpl_semi_sync_source_clients is '$CLIENTS', expected >= 1"

echo "[PASS] replication healthy, semi-sync ON, $CLIENTS client(s) attached"
exit 0
