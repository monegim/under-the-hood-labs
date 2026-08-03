#!/usr/bin/env bash
# Lab 6 check — is mysqld up, does the dedicated binlog filesystem have
# healthy free space again, and can we actually write a new row?
set -uo pipefail

PASS=0

echo "[check] checking mysql.service status..."
if systemctl is-active --quiet mysql; then
    echo "[check] mysql.service is active."
else
    echo "[FAIL] mysql.service is not active."
    systemctl status mysql --no-pager -l 2>&1 | head -10
    PASS=1
fi

if ! mountpoint -q /mnt/mysql-binlogs 2>/dev/null; then
    echo "[FAIL] /mnt/mysql-binlogs is not mounted."
    PASS=1
else
    echo "[check] /mnt/mysql-binlogs disk usage:"
    df -h /mnt/mysql-binlogs
    USE_PCT=$(df --output=pcent /mnt/mysql-binlogs | tail -1 | tr -d ' %')
    if [ "${USE_PCT:-100}" -ge 85 ]; then
        echo "[FAIL] /mnt/mysql-binlogs is still ${USE_PCT}% full - old binlogs likely not purged."
        PASS=1
    else
        echo "[check] /mnt/mysql-binlogs usage (${USE_PCT}%) looks healthy."
    fi
fi

if [ "$PASS" -eq 0 ]; then
    echo "[check] attempting a real write..."
    if mysql -uroot -prootpass appdb -e "INSERT INTO logs (payload) VALUES ('healthcheck');" 2>/tmp/lab06-check-err.log; then
        echo "[check] write succeeded."
    else
        echo "[FAIL] write failed:"
        cat /tmp/lab06-check-err.log
        PASS=1
    fi
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] mysqld is up, binlog disk usage is healthy, and writes succeed."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
