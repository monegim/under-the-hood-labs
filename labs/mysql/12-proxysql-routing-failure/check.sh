#!/usr/bin/env bash
# Lab 12 check — is ProxySQL routing writes to the actual writable
# server and reads to the actual read-only replica? Exits 0 only if
# both directions are correct.
set -uo pipefail

PASS=0

echo "[check] does a write via ProxySQL (port 6033) succeed?"
if docker exec lab12-primary mysql -h proxysql -P 6033 -u appuser -papppass appdb -e \
    "INSERT INTO orders (data) VALUES ('check-write');" 2>err.log; then
    echo "[check] write succeeded."
else
    echo "[FAIL] write via ProxySQL failed:"
    cat err.log
    PASS=1
fi
rm -f err.log

echo "[check] does a SELECT via ProxySQL land on the replica (server_id=2), not the primary?"
SERVER_ID=$(docker exec lab12-primary mysql -h proxysql -P 6033 -u appuser -papppass appdb -N -e \
    "SELECT @@server_id;" 2>/dev/null)
echo "[check] SELECT @@server_id via ProxySQL returned: ${SERVER_ID:-<none>}"
if [ "$SERVER_ID" = "2" ]; then
    echo "[check] reads are landing on the replica, as intended."
else
    echo "[FAIL] reads are not landing on the replica (expected server_id=2, got '${SERVER_ID:-<none>}')."
    PASS=1
fi

echo "[check] does mysql_servers show the correct (non-swapped) hostgroup assignment?"
ASSIGNMENT=$(docker exec lab12-proxysql mysql -h127.0.0.1 -P6032 -u admin -padmin -N -e \
    "SELECT hostgroup_id FROM mysql_servers WHERE hostname='primary';" 2>/dev/null)
echo "[check] primary is currently assigned to hostgroup_id=${ASSIGNMENT:-<none>}"
if [ "$ASSIGNMENT" = "10" ]; then
    echo "[check] primary is correctly in the write hostgroup (10)."
else
    echo "[FAIL] primary is in hostgroup '${ASSIGNMENT:-<none>}', expected 10 (the write hostgroup)."
    PASS=1
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] writes succeed against the writable server, reads land on the replica, hostgroups are correct."
    exit 0
else
    echo "[FAIL] routing is not correct yet — see details above."
    exit 1
fi
