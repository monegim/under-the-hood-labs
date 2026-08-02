#!/usr/bin/env bash
# Lab 13 check — is /var/log/myapp back under a safe usage threshold, and is
# the flooding process gone?
set -uo pipefail

PASS=0
THRESHOLD=80

if ! mountpoint -q /var/log/myapp 2>/dev/null; then
    echo "[FAIL] /var/log/myapp is not mounted."
    exit 1
fi

echo "[check] checking disk usage on /var/log/myapp..."
df -h /var/log/myapp
USE_PCT=$(df --output=pcent /var/log/myapp 2>/dev/null | tail -1 | tr -dc '0-9')

if [ -z "$USE_PCT" ]; then
    echo "[FAIL] could not determine usage percentage for /var/log/myapp."
    PASS=1
elif [ "$USE_PCT" -ge "$THRESHOLD" ]; then
    echo "[FAIL] /var/log/myapp is at ${USE_PCT}% - still at or above the ${THRESHOLD}% threshold."
    PASS=1
else
    echo "[check] /var/log/myapp is at ${USE_PCT}%, under the ${THRESHOLD}% threshold."
fi

echo "[check] checking for any lingering flaky-app writer processes..."
if pgrep -f 'flaky-app' >/dev/null 2>&1; then
    echo "[FAIL] a flaky-app writer process is still running:"
    pgrep -af 'flaky-app'
    PASS=1
else
    echo "[check] no flaky-app writer processes running."
fi

echo "[check] checking no other process still has a file open for writing under /var/log/myapp..."
OPEN_WRITERS=$(sudo lsof +D /var/log/myapp 2>/dev/null | awk 'NR>1 {print}')
if [ -n "$OPEN_WRITERS" ]; then
    echo "[FAIL] processes still have open file handles under /var/log/myapp:"
    echo "$OPEN_WRITERS"
    PASS=1
else
    echo "[check] no open file handles under /var/log/myapp."
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] /var/log/myapp usage is healthy and no runaway writer is active."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
