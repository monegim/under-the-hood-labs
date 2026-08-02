#!/usr/bin/env bash
# Lab 23 setup — builds an inode-exhaustion "writes fail, but df -h looks fine" incident.
#
# Mechanism: a dedicated loop-device filesystem formatted with a
# deliberately tiny inode count (`mkfs.ext4 -N 2000`), then filled with
# empty files until inodes run out. Blocks (bytes) barely move because
# every file is 0 bytes — so `df -h` stays low while `df -i` hits 100%.
#
# Using a dedicated loop-mounted filesystem (instead of the real root fs)
# keeps this safe and reversible: exhausting inodes on your actual root
# filesystem is disruptive and hard to undo cleanly; here it's just
# `umount` + `losetup -d`.
set -euo pipefail

echo "[1/5] Creating a 200M backing file for the lab filesystem..."
sudo mkdir -p /var/lib/inodelab
sudo dd if=/dev/zero of=/var/lib/inodelab/disk.img bs=1M count=200 status=none

echo "[2/5] Attaching it as a loop device..."
LOOPDEV=$(sudo losetup --find --show /var/lib/inodelab/disk.img)
echo "      loop device: $LOOPDEV"
echo "$LOOPDEV" | sudo tee /var/lib/inodelab/loopdev > /dev/null

echo "[3/5] Formatting with only 2000 inodes on purpose (-N 2000)..."
sudo mkfs.ext4 -q -N 2000 "$LOOPDEV"

echo "[4/5] Mounting at /mnt/appdata (imagine this is the app's data dir)..."
sudo mkdir -p /mnt/appdata
sudo mount "$LOOPDEV" /mnt/appdata
sudo chmod 777 /mnt/appdata

echo "[5/5] Simulating the app creating lots of small files (e.g. session/cache files)..."
set +e
i=0
while sudo -u nobody touch "/mnt/appdata/file_$i" 2>/dev/null; do
    i=$((i+1))
done
set -e

echo
echo "Done. Created $i files before running out of inodes."
echo
echo "Compare these two:"
echo "  df -h /mnt/appdata"
echo "  df -i /mnt/appdata"
echo
echo "To clean up later:"
echo "  sudo umount /mnt/appdata"
echo "  sudo losetup -d \$(cat /var/lib/inodelab/loopdev)"
echo "  sudo rm -rf /var/lib/inodelab"
