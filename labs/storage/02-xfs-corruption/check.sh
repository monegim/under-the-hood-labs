#!/usr/bin/env bash
# Lab 2 check — general health check: does the lab XFS filesystem mount
# cleanly, is it currently free of reported corruption, and can we
# actually read and write to it?
set -uo pipefail

PASS=0
STATE_DIR=/var/lib/xfslab
MNT=/mnt/xfsdata

if [ ! -f "$STATE_DIR/loopdev" ]; then
    echo "[FAIL] lab state not found - has setup.sh been run?"
    exit 1
fi
LOOPDEV=$(cat "$STATE_DIR/loopdev")

if ! mountpoint -q "$MNT" 2>/dev/null; then
    echo "[check] $MNT not mounted, attempting mount..."
    if ! sudo mount "$LOOPDEV" "$MNT" 2>&1; then
        echo "[FAIL] mount failed - filesystem is still corrupted."
        exit 1
    fi
fi

echo "[check] xfs_repair dry-run (-n, no changes) to check for outstanding corruption..."
sudo umount "$MNT" 2>/dev/null
if sudo xfs_repair -n "$LOOPDEV" 2>&1 | tee /tmp/xfs_check_$$.log; then
    if grep -qiE "corrupt|error|would" /tmp/xfs_check_$$.log; then
        echo "[FAIL] xfs_repair -n reports outstanding problems."
        PASS=1
    fi
else
    echo "[FAIL] xfs_repair -n exited non-zero - filesystem likely still corrupted."
    PASS=1
fi
rm -f /tmp/xfs_check_$$.log

sudo mount "$LOOPDEV" "$MNT" 2>/dev/null || true

echo "[check] attempting a real read+write test..."
TESTFILE="$MNT/.check_write_test_$$"
if echo "healthcheck" | sudo -u nobody tee "$TESTFILE" >/dev/null 2>&1 && sudo -u nobody cat "$TESTFILE" >/dev/null 2>&1; then
    echo "[check] read/write succeeded."
    sudo rm -f "$TESTFILE"
else
    echo "[FAIL] read/write test failed."
    PASS=1
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] $MNT is healthy - mounts cleanly, no reported corruption, read/write works."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
