#!/usr/bin/env bash
# Lab 19 check — verifies a query through ProxySQL succeeds cleanly.
#
# The client password is read live from ProxySQL's own mysql_users table
# rather than hardcoded. ProxySQL uses that one stored value both to
# authenticate the incoming client AND to authenticate itself to the
# backend, so this check passes only when that single value is actually
# consistent with what the backend accepts — no matter whether the fix was
# "sync ProxySQL to the backend's new password" or "roll the backend
# password back".
set -uo pipefail

PROXYSQL="lab19-proxysql"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying proxysql container is running..."
status=$(docker inspect -f '{{.State.Running}}' "$PROXYSQL" 2>/dev/null)
[ "$status" = "true" ] || fail "container $PROXYSQL is not running (run setup.sh first)"

echo "[check] reading appuser's current password from ProxySQL..."
APP_PASS=$(docker exec "$PROXYSQL" mysql -h127.0.0.1 -P6032 -uadmin -padmin -N -e \
  "SELECT password FROM mysql_users WHERE username='appuser';" 2>/dev/null)
[ -n "$APP_PASS" ] || fail "could not read appuser's password from ProxySQL's mysql_users table"

echo "[check] attempting a query as appuser through ProxySQL..."
OUT=$(docker exec "$PROXYSQL" mysql -h127.0.0.1 -P6033 -uappuser -p"$APP_PASS" appdb -N -e "SELECT 'ok';" 2>&1)
echo "$OUT" | grep -q "^ok$" || fail "query did not succeed: $OUT"

echo "[PASS] appuser can query through ProxySQL successfully."
exit 0
