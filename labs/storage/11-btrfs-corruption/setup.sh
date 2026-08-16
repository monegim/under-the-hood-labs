#!/usr/bin/env bash
# Lab 11 setup — builds a single-device btrfs corruption incident: a
# 300M loop-device-backed image formatted with btrfs (-d single -m dup,
# set explicitly rather than relying on mkfs.btrfs's version-dependent
# auto-detection), ~150M of sample data written and backed up outside
# the device, then a broad byte range corrupted directly on the
# underlying loop device (bypassing btrfs) - well inside the region the
# data actually landed on, sparing the superblock so it still mounts.
#
# Using a loop device keeps this safe and reversible: no real disk or
# partition is touched, and teardown is unmount + losetup -d.
set -euo pipefail

STATE_DIR=/var/lib/btrfslab
MNT=/mnt/btrfsdata

echo "[1/7] installing btrfs-progs if missing..."
if ! command -v mkfs.btrfs >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq btrfs-progs
fi

echo "[2/7] creating a 300M backing file..."
sudo mkdir -p "$STATE_DIR"
sudo dd if=/dev/zero of="$STATE_DIR/disk.img" bs=1M count=300 status=none

echo "[3/7] attaching it as a loop device..."
LOOPDEV=$(sudo losetup --find --show "$STATE_DIR/disk.img")
echo "$LOOPDEV" | sudo tee "$STATE_DIR/loopdev" > /dev/null
echo "      loop device: $LOOPDEV"

echo "[4/7] formatting with btrfs (-d single -m dup, set explicitly)..."
sudo mkfs.btrfs -f -d single -m dup -q "$LOOPDEV"
sudo mkdir -p "$MNT"
sudo mount "$LOOPDEV" "$MNT"
sudo chmod 777 "$MNT"

echo "[5/7] writing ~150M of sample data and keeping an untouched backup copy..."
for i in $(seq 1 10); do
    sudo -u nobody dd if=/dev/urandom of="$MNT/baseline_$i" bs=1M count=15 status=none
done
sudo mkdir -p "$STATE_DIR/backup"
sudo cp -a "$MNT/." "$STATE_DIR/backup/"

echo "[6/7] unmounting before corrupting (never corrupt a live block device"
echo "      outside of a challenge that does this deliberately)..."
sudo sync
sudo umount "$MNT"

echo "[7/7] corrupting bytes 100M-250M directly on the loop device - well"
echo "      inside the data region, sparing the superblock..."
sudo dd if=/dev/urandom of="$LOOPDEV" bs=1M seek=100 count=150 conv=notrunc

echo
echo "Done. The btrfs filesystem on $LOOPDEV has corrupted data underneath it."
echo
echo "Try:"
echo "  sudo mount $LOOPDEV $MNT"
echo "  sudo cat $MNT/baseline_1 > /dev/null; dmesg -T | tail -20"
echo
echo "To clean up later, see reset.sh."
