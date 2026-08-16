#!/usr/bin/env bash
# Lab 8 check — general health check of snapvg: is the origin mounted
# and writable, and is there no currently-Invalid snapshot sitting in the
# VG (an Invalid snapshot is not itself "unhealthy" for the origin, but
# it means an expected rollback point is silently gone, which is the
# thing this lab is actually about catching).
set -uo pipefail

PASS=0
VG=snapvg
MNT=/mnt/snaporigin

if ! sudo vgs "$VG" >/dev/null 2>&1; then
    echo "[FAIL] volume group '$VG' does not exist."
    exit 1
fi

echo "[check] lvs -a $VG:"
LVS_OUTPUT=$(sudo lvs -a -o+snap_percent "$VG" 2>&1)
echo "$LVS_OUTPUT"

if echo "$LVS_OUTPUT" | grep -qi "invalid"; then
    echo "[FAIL] an Invalid snapshot is present in $VG."
    PASS=1
fi

if mountpoint -q "$MNT" 2>/dev/null; then
    TESTFILE="$MNT/.check_write_test_$$"
    if echo "healthcheck" | sudo -u nobody tee "$TESTFILE" >/dev/null 2>&1; then
        echo "[check] write to $MNT succeeded."
        sudo rm -f "$TESTFILE"
    else
        echo "[FAIL] write to $MNT failed."
        PASS=1
    fi
else
    echo "[FAIL] $MNT is not mounted."
    PASS=1
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] $VG is healthy - origin is writable, no Invalid snapshots found."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
