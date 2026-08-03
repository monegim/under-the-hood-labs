#!/usr/bin/env bash
# Lab 5 reset — kill the victim service and any I/O/CPU hog processes,
# unmount and detach the loop device, remove state/logs, then re-run
# setup.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR=/var/lib/slowlab
LOG_DIR=/var/log/slowlab
MNT=/mnt/slowdata

echo "[reset] killing victim service and hog processes..."
if [ -f "$STATE_DIR/victim.pid" ]; then
    sudo kill "$(sudo cat "$STATE_DIR/victim.pid")" 2>/dev/null || true
fi
sudo pkill -f 'fio --name=hog' 2>/dev/null || true
sudo pkill yes 2>/dev/null || true

echo "[reset] unmounting $MNT if mounted..."
sudo umount "$MNT" 2>/dev/null || true

if [ -f "$STATE_DIR/loopdev" ]; then
    LOOPDEV=$(cat "$STATE_DIR/loopdev")
    echo "[reset] resetting I/O scheduler and detaching loop device $LOOPDEV..."
    DEV=$(basename "$LOOPDEV")
    echo none | sudo tee /sys/block/"$DEV"/queue/scheduler >/dev/null 2>&1 || true
    sudo losetup -d "$LOOPDEV" 2>/dev/null || true
fi

echo "[reset] detaching any other loop devices still pointing at the backing file..."
for dev in $(losetup -j "$STATE_DIR/disk.img" 2>/dev/null | cut -d: -f1); do
    sudo losetup -d "$dev" 2>/dev/null || true
done

echo "[reset] removing lab state and logs..."
sudo rm -rf "$STATE_DIR" "$LOG_DIR"

echo "[reset] re-running setup.sh to recreate the slow-disk incident..."
sudo bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
