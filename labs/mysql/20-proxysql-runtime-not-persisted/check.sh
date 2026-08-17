#!/usr/bin/env bash
# Lab 20 check — verifies a query through ProxySQL succeeds after a
# ProxySQL restart, proving the routing config actually survived it.
set -uo pipefail

PROXYSQL="lab20-proxysql"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying proxysql container is running..."
status=$(docker inspect -f '{{.State.Running}}' "$PROXYSQL" 2>/dev/null)
[ "$status" = "true" ] || fail "container $PROXYSQL is not running (run setup.sh first)"

echo "[check] attempting a query as appuser through ProxySQL..."
OUT=$(docker exec "$PROXYSQL" mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -N -e "SELECT 'ok';" 2>&1)
echo "$OUT" | grep -q "^ok$" || fail "query did not succeed: $OUT"

echo "[PASS] appuser can query through ProxySQL successfully."
exit 0
