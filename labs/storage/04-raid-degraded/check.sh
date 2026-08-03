#!/usr/bin/env bash
# Lab 4 check — general health check: is md0 fully synced (not
# degraded/failed), and can we actually write to it?
set -uo pipefail

PASS=0
MD=/dev/md0
MNT=/mnt/raiddata

if [ ! -e "$MD" ]; then
    echo "[FAIL] $MD does not exist."
    exit 1
fi

echo "[check] mdadm --detail $MD:"
sudo mdadm --detail "$MD"

STATE=$(sudo mdadm --detail "$MD" | awk -F': ' '/^ *State/{print $2; exit}')
echo "[check] array state: $STATE"
if echo "$STATE" | grep -qiE "degraded|fail"; then
    echo "[FAIL] array is degraded or failed."
    PASS=1
fi

if grep -qE "resync|recovery" /proc/mdstat 2>/dev/null; then
    echo "[check] a resync/recovery is still in progress:"
    cat /proc/mdstat
    echo "[FAIL] rebuild not yet complete."
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
    echo "[PASS] $MD is fully synced, not degraded, and writable."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
