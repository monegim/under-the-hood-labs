#!/usr/bin/env bash
# Lab 11 reset — unmount, detach the loop device, and blow away the
# backing file and backup entirely (setup.sh is not safe to re-run on
# top of an existing mount/loop device), then re-run setup.sh to
# recreate the corruption incident.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR=/var/lib/btrfslab
MNT=/mnt/btrfsdata

echo "[reset] unmounting $MNT if mounted..."
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

echo "[reset] re-running setup.sh to recreate the btrfs corruption incident..."
sudo bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
