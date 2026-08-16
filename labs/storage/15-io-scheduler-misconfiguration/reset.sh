#!/usr/bin/env bash
# Lab 15 reset — kills the hog and sensitive writer, tears down the
# cgroup, unmounts and detaches the loop device, removes lab state, and
# rebuilds via setup.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR=/var/lib/ioschedlab15
LOG_DIR=/var/log/ioschedlab15
MNT=/mnt/ioschedlab15
CGROUP=/sys/fs/cgroup/ioschedlab15

echo "[reset] killing lab processes..."
sudo pkill -f "$STATE_DIR/sensitive.sh" 2>/dev/null || true
sudo pkill -f "fio --name=schedhog" 2>/dev/null || true
sleep 1

echo "[reset] tearing down the cgroup..."
if [ -d "$CGROUP" ]; then
    for p in $(cat "$CGROUP/cgroup.procs" 2>/dev/null); do sudo kill -9 "$p" 2>/dev/null || true; done
    sleep 1
    sudo rmdir "$CGROUP" 2>/dev/null || true
fi

echo "[reset] unmounting and detaching the loop device..."
sudo umount "$MNT" 2>/dev/null || true
if [ -f "$STATE_DIR/loopdev" ]; then
    sudo losetup -d "$(cat "$STATE_DIR/loopdev")" 2>/dev/null || true
fi
for dev in $(losetup -j "$STATE_DIR/disk.img" 2>/dev/null | cut -d: -f1); do
    sudo losetup -d "$dev" 2>/dev/null || true
done

echo "[reset] removing lab state..."
sudo rm -rf "$STATE_DIR" "$LOG_DIR" "$MNT"

echo "[reset] rebuilding via setup.sh..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
