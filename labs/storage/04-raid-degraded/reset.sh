#!/usr/bin/env bash
# Lab 4 reset — stop the array, wipe member superblocks, detach loop
# devices, and remove backing files entirely (setup.sh is not safe to
# re-run on top of an existing array/mounts), then re-run setup.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR=/var/lib/raidlab
MNT=/mnt/raiddata
MD=/dev/md0

echo "[reset] restoring rebuild speed limit to default..."
sudo sh -c 'echo 200000 > /proc/sys/dev/raid/speed_limit_max' 2>/dev/null || true

echo "[reset] unmounting $MNT if mounted..."
sudo umount "$MNT" 2>/dev/null || true

echo "[reset] stopping array $MD if active..."
sudo mdadm --stop "$MD" 2>/dev/null || true

if [ -f "$STATE_DIR/loopdevs" ]; then
    echo "[reset] wiping member superblocks and detaching loop devices..."
    while read -r LOOP; do
        [ -n "$LOOP" ] || continue
        sudo mdadm --zero-superblock "$LOOP" 2>/dev/null || true
        sudo losetup -d "$LOOP" 2>/dev/null || true
    done < "$STATE_DIR/loopdevs"
fi

echo "[reset] detaching any other loop devices still pointing at lab backing files..."
for i in 1 2 3; do
    for dev in $(losetup -j "$STATE_DIR/disk$i.img" 2>/dev/null | cut -d: -f1); do
        sudo losetup -d "$dev" 2>/dev/null || true
    done
done

echo "[reset] removing lab state directory..."
sudo rm -rf "$STATE_DIR"

echo "[reset] re-running setup.sh to recreate the healthy RAID5 array..."
sudo bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
