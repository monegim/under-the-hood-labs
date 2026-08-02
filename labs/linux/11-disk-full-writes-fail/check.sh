#!/usr/bin/env bash
# Lab 11 check — can we currently write a new file to /mnt/appdata as the
# app user (nobody)? i.e. is inode/block exhaustion actually resolved?
set -uo pipefail

PASS=0
TESTFILE="/mnt/appdata/.check_write_test_$$"

if ! mountpoint -q /mnt/appdata 2>/dev/null; then
    echo "[FAIL] /mnt/appdata is not mounted."
    exit 1
fi

echo "[check] checking inode usage..."
df -i /mnt/appdata

echo "[check] checking block usage..."
df -h /mnt/appdata

echo "[check] attempting a real write as user 'nobody'..."
if echo "healthcheck" | sudo -u nobody tee "$TESTFILE" >/dev/null 2>&1; then
    echo "[check] write succeeded: $TESTFILE"
    sudo -u nobody rm -f "$TESTFILE" 2>/dev/null || sudo rm -f "$TESTFILE" 2>/dev/null
else
    echo "[FAIL] write as 'nobody' failed - disk/inode exhaustion is still present."
    PASS=1
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] writes to /mnt/appdata succeed - inode/disk exhaustion is resolved."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
