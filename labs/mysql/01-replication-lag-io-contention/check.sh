#!/usr/bin/env bash
# Lab 1 (Replication Lag / I/O Contention) — verifies replication is
# currently healthy: both replica threads running and Seconds_Behind_Source
# low, via SHOW REPLICA STATUS (MySQL 8.0.23+ terminology, matches the
# CHANGE REPLICATION SOURCE TO syntax used in setup.sh/README).
set -uo pipefail

PRIMARY="lab30-primary"
REPLICA="lab30-replica"
MAX_LAG_SECONDS=5

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying primary and replica containers are running..."
for c in "$PRIMARY" "$REPLICA"; do
  status=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
  [ "$status" = "true" ] || fail "container $c is not running (run setup.sh first)"
done

echo "[check] querying SHOW REPLICA STATUS on the replica..."
STATUS=$(docker exec "$REPLICA" mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" 2>/dev/null)
[ -n "$STATUS" ] || fail "could not query SHOW REPLICA STATUS on $REPLICA"

IO_RUNNING=$(echo "$STATUS" | awk -F': ' '/Replica_IO_Running:/{print $2; exit}')
SQL_RUNNING=$(echo "$STATUS" | awk -F': ' '/Replica_SQL_Running:/{print $2; exit}')
LAG=$(echo "$STATUS" | awk -F': ' '/Seconds_Behind_Source:/{print $2; exit}')

echo "[check] Replica_IO_Running=$IO_RUNNING Replica_SQL_Running=$SQL_RUNNING Seconds_Behind_Source=$LAG"

[ "$IO_RUNNING" = "Yes" ] || fail "Replica_IO_Running is not Yes (got '$IO_RUNNING')"
[ "$SQL_RUNNING" = "Yes" ] || fail "Replica_SQL_Running is not Yes (got '$SQL_RUNNING')"

if [ -z "$LAG" ] || [ "$LAG" = "NULL" ]; then
  fail "Seconds_Behind_Source is NULL/empty — replication is not applying"
fi

if ! echo "$LAG" | grep -qE '^[0-9]+$'; then
  fail "Seconds_Behind_Source is not numeric (got '$LAG')"
fi

if [ "$LAG" -gt "$MAX_LAG_SECONDS" ]; then
  fail "Seconds_Behind_Source is ${LAG}s (> ${MAX_LAG_SECONDS}s) — replication is lagging"
fi

echo "[PASS] replication is healthy: both threads running, Seconds_Behind_Source=${LAG}s"
exit 0
