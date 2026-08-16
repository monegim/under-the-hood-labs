#!/usr/bin/env bash
# Lab 9 setup — builds a "user hit their disk quota, filesystem has
# plenty of free space" incident: a 200M ext4 filesystem on a loop
# device, mounted with usrquota/grpquota, with user 'nobody' capped at a
# 20M soft / 25M hard block quota and already pushed past the hard limit.
#
# Using a loop device keeps this safe and reversible: no real disk or
# partition is touched, and teardown is unmount + losetup -d.
set -euo pipefail

STATE_DIR=/var/lib/quotalab
MNT=/mnt/quotadata

echo "[1/7] installing the quota package if missing..."
if ! command -v quotacheck >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq quota
fi

echo "[2/7] creating a 200M backing file..."
sudo mkdir -p "$STATE_DIR"
sudo dd if=/dev/zero of="$STATE_DIR/disk.img" bs=1M count=200 status=none

echo "[3/7] attaching it as a loop device..."
LOOPDEV=$(sudo losetup --find --show "$STATE_DIR/disk.img")
echo "$LOOPDEV" | sudo tee "$STATE_DIR/loopdev" > /dev/null
echo "      loop device: $LOOPDEV"

echo "[4/7] formatting with ext4 and mounting with usrquota,grpquota..."
sudo mkfs.ext4 -q "$LOOPDEV"
sudo mkdir -p "$MNT"
sudo mount -o usrquota,grpquota "$LOOPDEV" "$MNT"
sudo chmod 777 "$MNT"

echo "[5/7] initializing quota accounting..."
sudo quotacheck -cum "$MNT"
sudo quotaon "$MNT"

echo "[6/7] setting user 'nobody' to a 20M soft / 25M hard block quota..."
sudo setquota -u nobody 20000 25000 0 0 "$MNT"

echo "[7/7] writing past the hard limit as 'nobody'..."
set +e
sudo -u nobody dd if=/dev/zero of="$MNT/bigfile" bs=1M count=30 status=none 2>/dev/null
set -e

echo
echo "Done. Compare these:"
echo "  df -h $MNT              (filesystem layer - barely used)"
echo "  sudo quota -u nobody    (quota layer - at/past the hard limit)"
echo "  sudo repquota -a"
echo
echo "To clean up later, see reset.sh."
