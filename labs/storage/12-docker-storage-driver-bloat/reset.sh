#!/usr/bin/env bash
# Lab 12 reset — stops the lab's dedicated dockerd instance, unmounts
# and detaches the loop device, removes all lab state, then rebuilds
# from scratch via setup.sh. Never touches the host's real Docker.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR=/var/lib/dockerlab
MNT=/mnt/dockerlab
PIDFILE=/var/run/dockerlab.pid

echo "[reset] stopping the lab dockerd instance..."
if [ -f "$PIDFILE" ]; then
    sudo kill "$(cat "$PIDFILE")" 2>/dev/null || true
    sleep 2
fi
sudo pkill -f "dockerd --data-root $MNT" 2>/dev/null || true
sleep 1

echo "[reset] unmounting $MNT..."
sudo umount "$MNT" 2>/dev/null || true

echo "[reset] detaching the loop device..."
if [ -f "$STATE_DIR/loopdev" ]; then
    sudo losetup -d "$(cat "$STATE_DIR/loopdev")" 2>/dev/null || true
fi
# Belt and suspenders: detach anything still pointing at the backing file.
for dev in $(losetup -j "$STATE_DIR/disk.img" 2>/dev/null | cut -d: -f1); do
    sudo losetup -d "$dev" 2>/dev/null || true
done

echo "[reset] removing lab state..."
sudo rm -rf "$STATE_DIR" "$MNT"
sudo rm -f /var/run/dockerlab.sock "$PIDFILE" /var/log/dockerlab.log

echo "[reset] rebuilding via setup.sh..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
