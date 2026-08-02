#!/usr/bin/env bash
# Lab 2 setup — builds an XFS metadata-corruption incident on a loop
# device: a 200M XFS filesystem with sample data, corrupted with direct
# writes to the underlying block device, requiring xfs_repair.
#
# Using a dedicated loop device keeps this safe and reversible - real
# corruption tools only ever touch this throwaway backing file, never a
# real disk/partition.
set -euo pipefail

STATE_DIR=/var/lib/xfslab
MNT=/mnt/xfsdata

echo "[1/6] installing xfsprogs if missing..."
if ! command -v mkfs.xfs >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq xfsprogs
fi

echo "[2/6] creating a 200M backing file..."
sudo mkdir -p "$STATE_DIR"
sudo dd if=/dev/zero of="$STATE_DIR/disk.img" bs=1M count=200 status=none

echo "[3/6] attaching it as a loop device..."
LOOPDEV=$(sudo losetup --find --show "$STATE_DIR/disk.img")
echo "$LOOPDEV" | sudo tee "$STATE_DIR/loopdev" > /dev/null
echo "      loop device: $LOOPDEV"

echo "[4/6] formatting with XFS and writing sample app data..."
sudo mkfs.xfs -q "$LOOPDEV"
sudo mkdir -p "$MNT"
sudo mount "$LOOPDEV" "$MNT"
sudo chmod 777 "$MNT"
for i in $(seq 1 50); do
    sudo -u nobody dd if=/dev/urandom of="$MNT/app_data_$i" bs=4k count=8 status=none
done
sudo -u nobody mkdir -p "$MNT/subdir"
sudo -u nobody dd if=/dev/urandom of="$MNT/subdir/more_data" bs=4k count=8 status=none

echo "[5/6] unmounting before corrupting (never corrupt a live block device"
echo "      on purpose outside of Challenge A, which does this deliberately)..."
sudo umount "$MNT"

echo "[6/6] corrupting a block well inside the data/metadata region..."
sudo dd if=/dev/urandom of="$LOOPDEV" bs=4096 seek=2000 count=8 conv=notrunc

echo
echo "Done. The filesystem on $LOOPDEV is now corrupted."
echo
echo "Try:"
echo "  sudo mount $LOOPDEV $MNT"
echo "  dmesg -T | tail -40"
echo
echo "To clean up later, see reset.sh."
