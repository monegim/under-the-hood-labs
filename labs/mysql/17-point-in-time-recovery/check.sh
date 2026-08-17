#!/usr/bin/env bash
# Lab 17 check — verifies the restore target has the correct
# pre-disaster data (accounts 1-4, with id=1's balance updated), proving
# the backup + binlog replay actually recovered the right state.
set -uo pipefail

RESTORE="lab17-restore"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying restore container is running..."
status=$(docker inspect -f '{{.State.Running}}' "$RESTORE" 2>/dev/null)
[ "$status" = "true" ] || fail "container $RESTORE is not running (run setup.sh first)"

echo "[check] checking appdb.accounts exists on the restore target..."
ROWS=$(docker exec "$RESTORE" mysql -uroot -prootpass appdb -N -e "SELECT id, balance FROM accounts ORDER BY id;" 2>/dev/null)
[ -n "$ROWS" ] || fail "appdb.accounts is empty or missing on $RESTORE — did the backup/replay run?"

echo "[check] current restore target rows:"
echo "$ROWS"

EXPECTED=$'1\t150\n2\t200\n3\t300\n4\t400'
if [ "$ROWS" != "$EXPECTED" ]; then
    fail "restore target does not match the expected pre-disaster state (1:150, 2:200, 3:300, 4:400)"
fi

echo "[PASS] restore target has exactly the pre-disaster state — recovery succeeded."
exit 0
