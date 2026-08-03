#!/usr/bin/env bash
# Lab 7 (Binlog Corruption) check — verifies replication is currently
# healthy: both replica threads running and Seconds_Behind_Source low.
# (Recovering from binlog corruption in this lab means re-provisioning the
# replica from a fresh snapshot of the primary — see solution.md — so this
# check is intentionally the same shape as Lab 1/Lab 2's: it only cares
# that replication ends up healthy again, not which recovery path got you
# there.)
set -uo pipefail

PRIMARY="lab07-primary"
REPLICA="lab07-replica"
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
LAST_IO_ERRNO=$(echo "$STATUS" | awk -F': ' '/Last_IO_Errno:/{print $2; exit}')

echo "[check] Replica_IO_Running=$IO_RUNNING Replica_SQL_Running=$SQL_RUNNING Seconds_Behind_Source=$LAG Last_IO_Errno=$LAST_IO_ERRNO"

[ "$IO_RUNNING" = "Yes" ] || fail "Replica_IO_Running is not Yes (got '$IO_RUNNING', Last_IO_Errno=$LAST_IO_ERRNO) — binlog read error likely still unresolved"
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

echo "[check] confirming row counts match between primary and replica..."
PRIMARY_COUNT=$(docker exec "$PRIMARY" mysql -uroot -prootpass appdb -N -e "SELECT COUNT(*) FROM orders;" 2>/dev/null)
REPLICA_COUNT=$(docker exec "$REPLICA" mysql -uroot -prootpass appdb -N -e "SELECT COUNT(*) FROM orders;" 2>/dev/null)
echo "[check] primary orders count=$PRIMARY_COUNT   replica orders count=$REPLICA_COUNT"
[ "$PRIMARY_COUNT" = "$REPLICA_COUNT" ] || fail "row counts diverge between primary and replica"

echo "[PASS] replication is healthy: both threads running, Seconds_Behind_Source=${LAG}s, row counts match"
exit 0
