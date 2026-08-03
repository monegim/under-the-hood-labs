#!/usr/bin/env bash
# Lab 1 check — general health check of the labvg volume group: is
# lvapp (and, if the challenges were done, lvapp_thin/lvxfs) currently
# writable, and is no thin pool dangerously close to full?
set -uo pipefail

PASS=0

if ! sudo vgs labvg >/dev/null 2>&1; then
    echo "[FAIL] volume group 'labvg' does not exist."
    exit 1
fi

echo "[check] vgs / lvs labvg:"
sudo vgs labvg
sudo lvs labvg

check_mount_writable() {
    local mnt="$1"
    if ! mountpoint -q "$mnt" 2>/dev/null; then
        echo "[check] $mnt is not mounted - skipping (challenge not attempted, or not reset yet)."
        return 0
    fi
    local testfile="$mnt/.check_write_test_$$"
    if echo "healthcheck" | sudo -u nobody tee "$testfile" >/dev/null 2>&1; then
        echo "[check] write to $mnt succeeded."
        sudo rm -f "$testfile"
        return 0
    else
        echo "[FAIL] write to $mnt failed."
        return 1
    fi
}

check_mount_writable /mnt/appdata || PASS=1
check_mount_writable /mnt/thinapp || PASS=1
check_mount_writable /mnt/xfsapp || PASS=1

echo "[check] checking for any dangerously full thin pools..."
POOL_LINE=$(sudo lvs -a --noheadings -o lv_name,data_percent labvg 2>/dev/null | grep -i pool || true)
if [ -n "$POOL_LINE" ]; then
    echo "$POOL_LINE"
    DATA_PCT=$(echo "$POOL_LINE" | awk '{print $2}' | cut -d. -f1)
    if [ -n "$DATA_PCT" ] && [ "$DATA_PCT" -ge 95 ] 2>/dev/null; then
        echo "[FAIL] thin pool is at ${DATA_PCT}% data usage."
        PASS=1
    fi
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] labvg is healthy - mounted volumes are writable, no pool near full."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
