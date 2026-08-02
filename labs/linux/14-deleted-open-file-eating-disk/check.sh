#!/usr/bin/env bash
# Lab 14 check — is there currently no process holding a deleted-but-open
# large file under /var/tmp (this lab's target filesystem)?
set -uo pipefail

PASS=0
SIZE_THRESHOLD=$((1024 * 1024))  # 1MB

echo "[check] scanning for deleted-but-open files under /var/tmp via lsof +L1..."
DELETED=$(sudo lsof +L1 2>/dev/null | awk 'NR==1 || $0 ~ /\/var\/tmp/')
echo "$DELETED"

# Body rows only (skip header), filter to /var/tmp.
BAD_ROWS=$(echo "$DELETED" | awk 'NR>1 && /\/var\/tmp/ {print}')

if [ -z "$BAD_ROWS" ]; then
    echo "[check] no deleted-but-open files found under /var/tmp."
else
    echo "[check] found deleted-but-open file(s) under /var/tmp - checking size..."
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        SIZE=$(echo "$line" | awk '{print $7}')
        if [[ "$SIZE" =~ ^[0-9]+$ ]] && [ "$SIZE" -ge "$SIZE_THRESHOLD" ]; then
            echo "[FAIL] process still holding a large deleted file open (>=1MB): $line"
            PASS=1
        fi
    done <<< "$BAD_ROWS"
fi

echo "[check] confirming no known lab writer PIDs are still running..."
for pidfile in /var/tmp/lab26/writer.pid /var/tmp/lab26b/parent.pid /var/tmp/lab26b/child.pid; do
    if [ -f "$pidfile" ]; then
        PID=$(cat "$pidfile" 2>/dev/null)
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            echo "[FAIL] process from $pidfile (PID $PID) is still running."
            PASS=1
        fi
    fi
done

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] no process is holding a deleted-but-open large file under /var/tmp."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
