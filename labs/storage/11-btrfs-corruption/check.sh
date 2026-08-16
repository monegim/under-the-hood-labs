#!/usr/bin/env bash
# Lab 11 check — general health check: does the lab btrfs filesystem
# mount cleanly, can every baseline_* file be read back without a
# checksum/I-O error, and is it currently writable.
set -uo pipefail

PASS=0
STATE_DIR=/var/lib/btrfslab
MNT=/mnt/btrfsdata

if [ ! -f "$STATE_DIR/loopdev" ]; then
    echo "[FAIL] lab state not found - has setup.sh been run?"
    exit 1
fi
LOOPDEV=$(cat "$STATE_DIR/loopdev")

if ! mountpoint -q "$MNT" 2>/dev/null; then
    echo "[check] $MNT not mounted, attempting mount..."
    if ! sudo mount "$LOOPDEV" "$MNT" 2>&1; then
        echo "[FAIL] mount failed."
        exit 1
    fi
fi

echo "[check] reading back every baseline_* file..."
FOUND_ANY=0
for f in "$MNT"/baseline_*; do
    [ -e "$f" ] || continue
    FOUND_ANY=1
    if ! sudo cat "$f" > /dev/null 2>&1; then
        echo "[FAIL] read of $f failed - checksum/I-O error still present."
        PASS=1
    fi
done
if [ "$FOUND_ANY" -eq 0 ]; then
    echo "[FAIL] no baseline_* files found - has the filesystem been restored from backup?"
    PASS=1
fi

echo "[check] write test..."
TESTFILE="$MNT/.check_write_test_$$"
if echo "healthcheck" | sudo -u nobody tee "$TESTFILE" >/dev/null 2>&1; then
    echo "[check] write to $MNT succeeded."
    sudo rm -f "$TESTFILE"
else
    echo "[FAIL] write to $MNT failed."
    PASS=1
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] $MNT is healthy - mounts cleanly, all sample files readable, writable."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
