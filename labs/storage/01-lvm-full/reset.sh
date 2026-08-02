#!/usr/bin/env bash
# Lab 1 reset — tear down the labvg volume group completely (setup.sh is
# not safe to re-run on top of an existing VG/mounts), then re-run
# setup.sh to recreate the incident.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR=/var/lib/lvmlab
VG=labvg

echo "[reset] unmounting any lab mount points..."
for m in /mnt/appdata /mnt/thinapp /mnt/xfsapp; do
    sudo umount "$m" 2>/dev/null || true
done

echo "[reset] removing volume group $VG (if present)..."
sudo vgchange -an "$VG" 2>/dev/null || true
sudo vgremove -f "$VG" 2>/dev/null || true

echo "[reset] removing physical volumes and detaching loop devices..."
for f in loop1 loop2; do
    if [ -f "$STATE_DIR/$f" ]; then
        DEV=$(cat "$STATE_DIR/$f")
        sudo pvremove -ff -y "$DEV" 2>/dev/null || true
        sudo losetup -d "$DEV" 2>/dev/null || true
    fi
done

echo "[reset] detaching any other loop devices still pointing at lab backing files..."
for img in "$STATE_DIR"/disk1.img "$STATE_DIR"/disk2.img; do
    for dev in $(losetup -j "$img" 2>/dev/null | cut -d: -f1); do
        sudo losetup -d "$dev" 2>/dev/null || true
    done
done

echo "[reset] removing lab state directory..."
sudo rm -rf "$STATE_DIR"

echo "[reset] re-running setup.sh to recreate the LVM-full incident..."
sudo bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
