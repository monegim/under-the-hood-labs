#!/usr/bin/env bash
# Lab 15 check — verifies a fresh client connection through ProxySQL
# completes quickly, and that the backend's connection pool shows free
# capacity.
set -uo pipefail

PROXYSQL="lab15-proxysql"
TIMEOUT_SECONDS=5

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying proxysql container is running..."
status=$(docker inspect -f '{{.State.Running}}' "$PROXYSQL" 2>/dev/null)
[ "$status" = "true" ] || fail "container $PROXYSQL is not running (run setup.sh first)"

echo "[check] attempting a fresh client connection through proxysql (timeout ${TIMEOUT_SECONDS}s)..."
if ! timeout "$TIMEOUT_SECONDS" docker exec "$PROXYSQL" mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -e "SELECT 1;" >/dev/null 2>&1; then
    fail "a fresh connection through proxysql did not complete within ${TIMEOUT_SECONDS}s"
fi

echo "[check] checking the backend connection pool for free capacity..."
POOL=$(docker exec "$PROXYSQL" mysql -h127.0.0.1 -P6032 -uadmin -padmin -N -e \
  "SELECT ConnFree FROM stats_mysql_connection_pool WHERE hostgroup=10;" 2>/dev/null)
echo "[check] ConnFree=$POOL"
if [ -z "$POOL" ] || [ "$POOL" -lt 1 ] 2>/dev/null; then
    fail "backend connection pool has no free capacity (ConnFree=${POOL:-<empty>})"
fi

echo "[PASS] fresh connections through proxysql succeed quickly, pool has free capacity."
exit 0
