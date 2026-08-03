#!/usr/bin/env bash
# Lab 6 check — general health check: is the currently-active lab device
# a healthy mapping (not flakey/error), and does a real write+read+
# checksum round-trip succeed without I/O error?
set -uo pipefail

PASS=0
MNT=/mnt/nvmedata
STATE_DIR=/var/lib/nvmelab

if ! mountpoint -q "$MNT" 2>/dev/null; then
    echo "[FAIL] $MNT is not mounted."
    exit 1
fi

echo "[check] active device-mapper targets on the lab's storage:"
sudo dmsetup ls 2>/dev/null | grep -i nvme || echo "(no dm-flakey/dm-error targets active - likely replaced with a plain device)"

for name in nvme0 nvme0-dead nvme0-corrupt; do
    if sudo dmsetup info "$name" >/dev/null 2>&1; then
        TABLE=$(sudo dmsetup table "$name" 2>/dev/null)
        echo "[check] $name table: $TABLE"
        if echo "$TABLE" | grep -qE "flakey|error"; then
            echo "[FAIL] $name is still a flakey/error mapping - drive has not been 'replaced'."
            PASS=1
        fi
    fi
done

echo "[check] round-trip write/read/checksum test..."
TESTFILE="$MNT/.check_test_$$"
CONTENT="healthcheck-$$"
if echo "$CONTENT" | sudo tee "$TESTFILE" >/dev/null 2>&1; then
    READBACK=$(sudo cat "$TESTFILE" 2>/dev/null)
    if [ "$READBACK" = "$CONTENT" ]; then
        echo "[check] write/read/checksum round-trip matched."
    else
        echo "[FAIL] data read back does not match what was written (silent corruption?)."
        PASS=1
    fi
    sudo rm -f "$TESTFILE"
else
    echo "[FAIL] write failed - device still erroring."
    PASS=1
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] $MNT is on a healthy device and round-trips data correctly."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
