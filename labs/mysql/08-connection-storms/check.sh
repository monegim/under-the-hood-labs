#!/usr/bin/env bash
# Lab 8 check — verifies connections have real headroom again and a new
# app connection actually succeeds.
set -uo pipefail

fail() { echo "[FAIL] $1"; exit 1; }

if ! systemctl is-active --quiet mysql; then
    fail "mysql.service is not active"
fi

echo "[check] checking Threads_connected vs max_connections..."
THREADS=$(mysql -uroot -prootpass -N -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null | awk '{print $2}')
MAXCONN=$(mysql -uroot -prootpass -N -e "SHOW VARIABLES LIKE 'max_connections';" 2>/dev/null | awk '{print $2}')
echo "[check] Threads_connected=$THREADS max_connections=$MAXCONN"

[ -n "$THREADS" ] && [ -n "$MAXCONN" ] || fail "could not read connection status from MySQL"

HEADROOM=$((MAXCONN - THREADS))
if [ "$HEADROOM" -lt 10 ]; then
    fail "only $HEADROOM connection(s) of headroom left (Threads_connected=$THREADS, max_connections=$MAXCONN)"
fi
echo "[check] $HEADROOM connections of headroom - looks healthy."

echo "[check] checking for a pile of sleeping appuser connections..."
SLEEPERS=$(mysql -uroot -prootpass -N -e "
  SELECT COUNT(*) FROM information_schema.processlist WHERE user='appuser' AND command='Sleep';
" 2>/dev/null)
echo "[check] sleeping appuser connections: ${SLEEPERS:-0}"
if [ "${SLEEPERS:-0}" -gt 10 ]; then
    fail "$SLEEPERS idle appuser connections still open - the storm hasn't actually been cleaned up"
fi

echo "[check] attempting a real new connection as appuser..."
if mysql -uappuser -pappuserpass appdb -e "SELECT 1;" > /dev/null 2>/tmp/lab08-check-err.log; then
    echo "[check] new appuser connection succeeded."
else
    echo "[FAIL] new appuser connection failed:"
    cat /tmp/lab08-check-err.log
    exit 1
fi

echo "[PASS] connection headroom is healthy and new connections succeed."
exit 0
