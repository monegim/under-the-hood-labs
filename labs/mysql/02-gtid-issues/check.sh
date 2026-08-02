#!/usr/bin/env bash
# Lab 2 (GTID Errant Transaction) check — verifies replication is currently
# healthy: both replica threads running and Seconds_Behind_Source low.
set -uo pipefail

PRIMARY="lab02-primary"
REPLICA="lab02-replica"
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
LAST_SQL_ERRNO=$(echo "$STATUS" | awk -F': ' '/Last_SQL_Errno:/{print $2; exit}')

echo "[check] Replica_IO_Running=$IO_RUNNING Replica_SQL_Running=$SQL_RUNNING Seconds_Behind_Source=$LAG Last_SQL_Errno=$LAST_SQL_ERRNO"

[ "$IO_RUNNING" = "Yes" ] || fail "Replica_IO_Running is not Yes (got '$IO_RUNNING')"
[ "$SQL_RUNNING" = "Yes" ] || fail "Replica_SQL_Running is not Yes (got '$SQL_RUNNING', Last_SQL_Errno=$LAST_SQL_ERRNO) — GTID conflict still unresolved"

if [ -z "$LAG" ] || [ "$LAG" = "NULL" ]; then
  fail "Seconds_Behind_Source is NULL/empty — replication is not applying"
fi

if ! echo "$LAG" | grep -qE '^[0-9]+$'; then
  fail "Seconds_Behind_Source is not numeric (got '$LAG')"
fi

if [ "$LAG" -gt "$MAX_LAG_SECONDS" ]; then
  fail "Seconds_Behind_Source is ${LAG}s (> ${MAX_LAG_SECONDS}s) — replication is lagging"
fi

echo "[check] confirming the disputed row now matches between primary and replica..."
PRIMARY_ROW=$(docker exec "$PRIMARY" mysql -uroot -prootpass appdb -N -e "SELECT data FROM orders WHERE id=9999;" 2>/dev/null)
REPLICA_ROW=$(docker exec "$REPLICA" mysql -uroot -prootpass appdb -N -e "SELECT data FROM orders WHERE id=9999;" 2>/dev/null)
echo "[check] primary id=9999 -> '$PRIMARY_ROW'   replica id=9999 -> '$REPLICA_ROW'"
[ "$PRIMARY_ROW" = "$REPLICA_ROW" ] || fail "row id=9999 still diverges between primary and replica — reconcile the data before skipping the GTID"

echo "[PASS] replication is healthy: both threads running, Seconds_Behind_Source=${LAG}s, id=9999 reconciled"
exit 0
