#!/usr/bin/env bash
# Lab 8 reset — tear down snapvg completely (setup.sh is not safe to
# re-run on top of an existing VG/mounts), then re-run setup.sh to
# recreate the invalid-snapshot incident.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR=/var/lib/lvmsnaplab
VG=snapvg

echo "[reset] unmounting any lab mount points..."
for m in /mnt/snaporigin /mnt/snap1; do
    sudo umount "$m" 2>/dev/null || true
done

echo "[reset] removing volume group $VG (if present)..."
sudo vgchange -an "$VG" 2>/dev/null || true
sudo vgremove -f "$VG" 2>/dev/null || true

echo "[reset] removing physical volume and detaching loop device..."
if [ -f "$STATE_DIR/loopdev" ]; then
    LOOPDEV=$(cat "$STATE_DIR/loopdev")
    sudo pvremove -ff -y "$LOOPDEV" 2>/dev/null || true
    sudo losetup -d "$LOOPDEV" 2>/dev/null || true
fi

echo "[reset] detaching any other loop devices still pointing at the backing file..."
for dev in $(losetup -j "$STATE_DIR/disk.img" 2>/dev/null | cut -d: -f1); do
    sudo losetup -d "$dev" 2>/dev/null || true
done

echo "[reset] removing lab state directory..."
sudo rm -rf "$STATE_DIR"

echo "[reset] re-running setup.sh to recreate the invalid-snapshot incident..."
sudo bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
