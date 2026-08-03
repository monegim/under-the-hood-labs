#!/usr/bin/env bash
# Lab 3 check — general health check: does the lab ext4 filesystem mount
# cleanly, does e2fsck -n report it clean, and can we read/write it?
set -uo pipefail

PASS=0
STATE_DIR=/var/lib/ext4lab
MNT=/mnt/ext4data

if [ ! -f "$STATE_DIR/loopdev" ]; then
    echo "[FAIL] lab state not found - has setup.sh been run?"
    exit 1
fi
LOOPDEV=$(cat "$STATE_DIR/loopdev")

if ! mountpoint -q "$MNT" 2>/dev/null; then
    echo "[check] $MNT not mounted, attempting mount..."
    if ! sudo mount "$LOOPDEV" "$MNT" 2>&1; then
        echo "[FAIL] mount failed - superblock/filesystem likely still broken."
        exit 1
    fi
fi

echo "[check] e2fsck -n (read-only check) while unmounted..."
sudo umount "$MNT" 2>/dev/null
if ! sudo e2fsck -n "$LOOPDEV"; then
    echo "[FAIL] e2fsck -n reports outstanding problems."
    PASS=1
fi
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
    echo "[PASS] $MNT is healthy - mounts cleanly, e2fsck reports clean, read/write works."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
