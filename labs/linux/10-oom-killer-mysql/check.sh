#!/usr/bin/env bash
# Lab 10 check — is mysqld currently up and NOT in a fresh OOM-kill loop?
set -uo pipefail

PASS=0

echo "[check] checking mysql.service status..."
if systemctl is-active --quiet mysql; then
    echo "[check] mysql.service is active (running)."
else
    echo "[FAIL] mysql.service is not active. Current status:"
    systemctl status mysql --no-pager -l 2>&1 | head -10
    PASS=1
fi

echo "[check] confirming mysqld process is actually alive..."
if pgrep -x mysqld >/dev/null 2>&1; then
    echo "[check] mysqld process found."
else
    echo "[FAIL] no running mysqld process found."
    PASS=1
fi

echo "[check] looking for a FRESH OOM kill of mysqld in the last minute..."
RECENT_OOM=$(sudo journalctl -k --since "1 min ago" 2>/dev/null | grep -i -E "killed process.*mysqld|oom.*mysqld" || true)
if [ -n "$RECENT_OOM" ]; then
    echo "[FAIL] a recent OOM kill of mysqld was found in the last minute:"
    echo "$RECENT_OOM"
    PASS=1
else
    echo "[check] no OOM kill of mysqld in the last minute (older kill evidence from the original incident is expected and fine)."
fi

echo "[check] checking mysql.service restart count isn't actively climbing (crash-loop check)..."
NRESTARTS=$(systemctl show mysql.service -p NRestarts --value 2>/dev/null || echo "0")
ACTIVE_STATE=$(systemctl show mysql.service -p ActiveState --value 2>/dev/null || echo "unknown")
ACTIVE_ENTER=$(systemctl show mysql.service -p ActiveEnterTimestamp --value 2>/dev/null || echo "")
echo "[check] mysql.service ActiveState=$ACTIVE_STATE NRestarts=$NRestarts ActiveEnterTimestamp=$ACTIVE_ENTER"
if [ "$ACTIVE_STATE" = "active" ]; then
    ENTER_EPOCH=$(date -d "$ACTIVE_ENTER" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    if [ "$ENTER_EPOCH" -gt 0 ] && [ $((NOW_EPOCH - ENTER_EPOCH)) -lt 60 ] && [ "$NRESTARTS" -gt 0 ] 2>/dev/null; then
        RECENT_KILLS=$(sudo journalctl -k --since "3 min ago" 2>/dev/null | grep -c -i "killed process.*mysqld" || true)
        if [ "${RECENT_KILLS:-0}" -gt 1 ]; then
            echo "[FAIL] mysql.service started less than a minute ago with $NRESTARTS restarts and $RECENT_KILLS OOM kills in the last 3 min - looks like an active crash loop."
            PASS=1
        fi
    fi
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] mysqld is running, not currently OOM-killed, and not in an active crash loop."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
