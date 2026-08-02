#!/usr/bin/env bash
# Lab 11 reset — tear down the loop device/mount/backing file completely
# (setup.sh is not safe to re-run on top of an existing mount/loop device),
# then re-run setup.sh to recreate the inode-exhaustion incident.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] unmounting /mnt/appdata if mounted..."
sudo umount /mnt/appdata 2>/dev/null || true

if [ -f /var/lib/inodelab/loopdev ]; then
    LOOPDEV=$(cat /var/lib/inodelab/loopdev)
    echo "[reset] detaching loop device $LOOPDEV if attached..."
    sudo losetup -d "$LOOPDEV" 2>/dev/null || true
fi

echo "[reset] detaching any other loop devices still pointing at the lab's backing file..."
for dev in $(losetup -j /var/lib/inodelab/disk.img 2>/dev/null | cut -d: -f1); do
    sudo losetup -d "$dev" 2>/dev/null || true
done

echo "[reset] removing lab state directory..."
sudo rm -rf /var/lib/inodelab

echo "[reset] re-running setup.sh to recreate the inode-exhaustion incident..."
sudo bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
