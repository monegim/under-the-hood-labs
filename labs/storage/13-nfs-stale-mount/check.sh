#!/usr/bin/env bash
# Lab 13 check — verifies the client mount is CURRENTLY healthy: a
# fresh read against it succeeds with no stale-handle/IO error. Checks
# the observable state, not which specific recovery command got there.
set -uo pipefail

MNT=/mnt/nfslab13
PASS=0

echo "[check] is $MNT actually mounted?"
if ! mountpoint -q "$MNT" 2>/dev/null; then
    echo "[FAIL] $MNT is not currently a mount point."
    exit 1
fi

echo "[check] does a fresh read against it succeed?"
if timeout 5 cat "$MNT/data.txt" >/tmp/lab13_check_out 2>/tmp/lab13_check_err; then
    echo "[check] read succeeded: $(cat /tmp/lab13_check_out)"
else
    echo "[FAIL] read failed or timed out:"
    cat /tmp/lab13_check_err 2>/dev/null
    PASS=1
fi
rm -f /tmp/lab13_check_out /tmp/lab13_check_err

echo "[check] does a fresh write against it succeed?"
if echo "check-write-$(date +%s)" | timeout 5 sudo tee "$MNT/checkfile.txt" >/dev/null 2>/tmp/lab13_check_werr; then
    echo "[check] write succeeded."
else
    echo "[FAIL] write failed or timed out:"
    cat /tmp/lab13_check_werr 2>/dev/null
    PASS=1
fi
rm -f /tmp/lab13_check_werr

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] NFS mount is healthy — reads and writes both succeed."
    exit 0
else
    echo "[FAIL] mount is not healthy yet — see details above."
    exit 1
fi
