#!/usr/bin/env bash
# Lab 10 reset — destroy labpool completely (setup.sh is not safe to
# re-run on top of an existing pool), then re-run setup.sh to recreate
# the degraded-pool incident.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR=/var/lib/zfslab
POOL=labpool

echo "[reset] destroying pool $POOL (if present)..."
sudo zpool destroy "$POOL" 2>/dev/null || true

echo "[reset] detaching loop devices..."
if [ -f "$STATE_DIR/loopdevs" ]; then
    while read -r dev; do
        sudo losetup -d "$dev" 2>/dev/null || true
    done < "$STATE_DIR/loopdevs"
fi

echo "[reset] detaching any other loop devices still pointing at the backing files..."
for img in "$STATE_DIR"/disk1.img "$STATE_DIR"/disk2.img "$STATE_DIR"/disk3.img "$STATE_DIR"/disk4.img; do
    for dev in $(losetup -j "$img" 2>/dev/null | cut -d: -f1); do
        sudo losetup -d "$dev" 2>/dev/null || true
    done
done

echo "[reset] removing lab state directory..."
sudo rm -rf "$STATE_DIR"

echo "[reset] re-running setup.sh to recreate the degraded-pool incident..."
sudo bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
