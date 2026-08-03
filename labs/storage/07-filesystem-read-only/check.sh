#!/usr/bin/env bash
# Lab 7 check — general health check: is /mnt/rodata currently mounted
# rw and writable, and has it stayed that way (no recent remount-ro
# events), rather than just happening to be rw at this exact instant?
set -uo pipefail

PASS=0
MNT=/mnt/rodata

if ! mountpoint -q "$MNT" 2>/dev/null; then
    echo "[FAIL] $MNT is not mounted."
    exit 1
fi

echo "[check] current mount options:"
mount | grep " $MNT " || true

if mount | grep " $MNT " | grep -qE '\(ro[,)]'; then
    echo "[FAIL] $MNT is currently mounted read-only."
    PASS=1
fi

echo "[check] attempting a real write..."
TESTFILE="$MNT/.check_write_test_$$"
if echo "healthcheck" | sudo tee "$TESTFILE" >/dev/null 2>&1; then
    echo "[check] write succeeded."
    sudo rm -f "$TESTFILE"
else
    echo "[FAIL] write failed even though mount shows rw."
    PASS=1
fi

echo "[check] checking for repeated remount-ro events in the last few minutes..."
COUNT=$(dmesg -T 2>/dev/null | grep -ic "remount.*read-only\|read-only.*remount" || true)
echo "[check] remount-ro events seen in dmesg buffer: $COUNT"
if [ "$COUNT" -ge 2 ] 2>/dev/null; then
    echo "[FAIL] filesystem has flipped read-only more than once - underlying issue likely not fixed."
    PASS=1
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] $MNT is stably mounted read-write and writable."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
