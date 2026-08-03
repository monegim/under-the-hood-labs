#!/usr/bin/env bash
# Lab 3 setup — builds an ext4 "bad primary superblock" incident on a
# loop device: format, capture backup superblock locations, write sample
# data, then zero the primary superblock directly with dd.
#
# Using a dedicated loop device keeps this safe and reversible - real
# corruption tools only ever touch this throwaway backing file, never a
# real disk/partition.
set -euo pipefail

STATE_DIR=/var/lib/ext4lab
MNT=/mnt/ext4data

echo "[1/6] creating a 200M backing file..."
sudo mkdir -p "$STATE_DIR"
sudo dd if=/dev/zero of="$STATE_DIR/disk.img" bs=1M count=200 status=none

echo "[2/6] attaching it as a loop device..."
LOOPDEV=$(sudo losetup --find --show "$STATE_DIR/disk.img")
echo "$LOOPDEV" | sudo tee "$STATE_DIR/loopdev" > /dev/null
echo "      loop device: $LOOPDEV"

echo "[3/6] formatting with ext4..."
sudo mkfs.ext4 -q "$LOOPDEV"

echo "[4/6] recording backup superblock locations BEFORE anything goes wrong..."
sudo mke2fs -n "$LOOPDEV" | tee "$STATE_DIR/backup_superblocks.txt" > /dev/null
sudo chmod 644 "$STATE_DIR/backup_superblocks.txt"
cat "$STATE_DIR/backup_superblocks.txt"

echo "[5/6] mounting and writing sample app data..."
sudo mkdir -p "$MNT"
sudo mount "$LOOPDEV" "$MNT"
sudo chmod 777 "$MNT"
for i in $(seq 1 10); do
    sudo -u nobody dd if=/dev/urandom of="$MNT/app_data_$i" bs=4k count=4 status=none
done
sudo umount "$MNT"

echo "[6/6] zeroing the primary superblock (1024 bytes at offset 1024)..."
sudo dd if=/dev/zero of="$LOOPDEV" bs=1024 seek=1 count=1 conv=notrunc

echo
echo "Done. Try:"
echo "  sudo mount $LOOPDEV $MNT     # will fail - bad superblock"
echo "  sudo e2fsck -n $LOOPDEV      # diagnose only"
echo
echo "Backup superblock locations are in:"
echo "  $STATE_DIR/backup_superblocks.txt"
echo
echo "To clean up later, see reset.sh."
