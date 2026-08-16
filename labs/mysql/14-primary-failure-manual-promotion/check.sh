#!/usr/bin/env bash
# Lab 14 check — works out which replica was promoted (whichever has
# read_only=OFF), verifies the other one is actively replicating from
# it without errors, and that both agree on the data.
set -uo pipefail

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] figuring out which replica was promoted..."
NEW_PRIMARY=""
FOLLOWER=""
for r in lab14-replica-a lab14-replica-b; do
  running=$(docker inspect -f '{{.State.Running}}' "$r" 2>/dev/null)
  [ "$running" = "true" ] || fail "container $r is not running"
  RO=$(docker exec "$r" mysql -uroot -prootpass -N -e "SELECT @@GLOBAL.read_only;" 2>/dev/null)
  if [ "$RO" = "0" ]; then
    NEW_PRIMARY="$r"
  fi
done

[ -n "$NEW_PRIMARY" ] || fail "neither replica-a nor replica-b has read_only=OFF — nothing has been promoted yet"
echo "[check] $NEW_PRIMARY has read_only=OFF — treating it as the promoted primary"

if [ "$NEW_PRIMARY" = "lab14-replica-a" ]; then
  FOLLOWER="lab14-replica-b"
else
  FOLLOWER="lab14-replica-a"
fi

echo "[check] verifying $FOLLOWER is actively replicating from $NEW_PRIMARY..."
STATUS=$(docker exec "$FOLLOWER" mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" 2>/dev/null)
echo "$STATUS" | grep -q "Replica_IO_Running: Yes" || fail "$FOLLOWER's replica IO thread is not running"
echo "$STATUS" | grep -q "Replica_SQL_Running: Yes" || fail "$FOLLOWER's replica SQL thread is not running"
SOURCE_HOST=$(echo "$STATUS" | grep "Source_Host" | awk '{print $2}')
EXPECTED_HOST="${NEW_PRIMARY#lab14-}"
if [ "$SOURCE_HOST" != "$EXPECTED_HOST" ]; then
    fail "$FOLLOWER is replicating from '$SOURCE_HOST', not the promoted primary ('$EXPECTED_HOST')"
fi
echo "[check] $FOLLOWER is following $NEW_PRIMARY correctly."

echo "[check] comparing data between the two..."
PRIMARY_ROWS=$(docker exec "$NEW_PRIMARY" mysql -uroot -prootpass appdb -N -e "SELECT COUNT(*) FROM orders;" 2>/dev/null)
FOLLOWER_ROWS=$(docker exec "$FOLLOWER" mysql -uroot -prootpass appdb -N -e "SELECT COUNT(*) FROM orders;" 2>/dev/null)
echo "[check] $NEW_PRIMARY has $PRIMARY_ROWS orders, $FOLLOWER has $FOLLOWER_ROWS orders"
[ "$PRIMARY_ROWS" = "$FOLLOWER_ROWS" ] || fail "row counts don't match — $FOLLOWER hasn't fully caught up"

echo "[PASS] $NEW_PRIMARY is promoted and writable, $FOLLOWER is following it correctly, data matches."
exit 0
