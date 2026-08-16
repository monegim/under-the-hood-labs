#!/usr/bin/env bash
# Lab 9 reset — tear down the quota lab filesystem completely (setup.sh
# is not safe to re-run on top of an existing mount), then re-run
# setup.sh to recreate the quota-exceeded incident.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR=/var/lib/quotalab
MNT=/mnt/quotadata

echo "[reset] turning off quota and unmounting $MNT if mounted..."
sudo quotaoff "$MNT" 2>/dev/null || true
sudo umount "$MNT" 2>/dev/null || true

if [ -f "$STATE_DIR/loopdev" ]; then
    LOOPDEV=$(cat "$STATE_DIR/loopdev")
    echo "[reset] detaching loop device $LOOPDEV if attached..."
    sudo losetup -d "$LOOPDEV" 2>/dev/null || true
fi

echo "[reset] detaching any other loop devices still pointing at the backing file..."
for dev in $(losetup -j "$STATE_DIR/disk.img" 2>/dev/null | cut -d: -f1); do
    sudo losetup -d "$dev" 2>/dev/null || true
done

echo "[reset] removing lab state directory..."
sudo rm -rf "$STATE_DIR"

echo "[reset] re-running setup.sh to recreate the quota-exceeded incident..."
sudo bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
