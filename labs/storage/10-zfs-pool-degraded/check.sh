#!/usr/bin/env bash
# Lab 10 check — general health check: is labpool ONLINE (not DEGRADED
# or FAULTED), and is it currently writable.
set -uo pipefail

PASS=0
POOL=labpool
MNT=/mnt/zfsdata

if ! sudo zpool status "$POOL" >/dev/null 2>&1; then
    echo "[FAIL] pool '$POOL' does not exist."
    exit 1
fi

echo "[check] zpool status $POOL:"
sudo zpool status "$POOL"

STATE=$(sudo zpool status "$POOL" | awk '/^ *state:/{print $2; exit}')
echo "[check] pool state: $STATE"
if [ "$STATE" != "ONLINE" ]; then
    echo "[FAIL] pool is not ONLINE (state: $STATE)."
    PASS=1
fi

if mountpoint -q "$MNT" 2>/dev/null; then
    TESTFILE="$MNT/.check_write_test_$$"
    if echo "healthcheck" | sudo tee "$TESTFILE" >/dev/null 2>&1; then
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
    echo "[PASS] $POOL is ONLINE and writable."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
