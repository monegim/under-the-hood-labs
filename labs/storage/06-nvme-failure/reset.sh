#!/usr/bin/env bash
# Lab 6 reset — kill the writer loop, unmount, remove any dm-flakey/
# dm-error/plain mappings the lab or its challenges created, detach loop
# devices, remove state/logs, then re-run setup.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR=/var/lib/nvmelab
LOG_DIR=/var/log/nvmelab
MNT=/mnt/nvmedata

echo "[reset] killing writer loop..."
if [ -f "$STATE_DIR/writer.pid" ]; then
    sudo kill "$(sudo cat "$STATE_DIR/writer.pid")" 2>/dev/null || true
fi

echo "[reset] unmounting $MNT if mounted..."
sudo umount "$MNT" 2>/dev/null || true

echo "[reset] removing any dm targets the lab or its challenges created..."
for name in nvme0 nvme0-dead nvme0-corrupt; do
    sudo dmsetup remove "$name" 2>/dev/null || true
done

if [ -f "$STATE_DIR/loopdev" ]; then
    LOOPDEV=$(cat "$STATE_DIR/loopdev")
    echo "[reset] detaching loop device $LOOPDEV..."
    sudo losetup -d "$LOOPDEV" 2>/dev/null || true
fi

echo "[reset] detaching any other loop devices pointing at lab backing files..."
for img in "$STATE_DIR"/disk.img "$STATE_DIR"/disk_replacement.img; do
    for dev in $(losetup -j "$img" 2>/dev/null | cut -d: -f1); do
        sudo losetup -d "$dev" 2>/dev/null || true
    done
done

echo "[reset] removing lab state and logs..."
sudo rm -rf "$STATE_DIR" "$LOG_DIR"

echo "[reset] re-running setup.sh to recreate the simulated drive failure..."
sudo bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
