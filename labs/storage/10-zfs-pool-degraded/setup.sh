#!/usr/bin/env bash
# Lab 10 setup — builds a small ZFS raidz1 pool out of three loop-device-
# backed images, writes sample data, then takes one member offline to
# simulate a failed drive, leaving the pool DEGRADED.
#
# Using loop devices keeps this safe and reversible: no real disks are
# touched, and teardown is zpool destroy + losetup -d.
set -euo pipefail

STATE_DIR=/var/lib/zfslab
POOL=labpool
MNT=/mnt/zfsdata

echo "[1/7] installing zfsutils-linux if missing (may build DKMS modules - can take a few minutes)..."
if ! command -v zpool >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq zfsutils-linux
fi

echo "[2/7] loading the zfs kernel module..."
sudo modprobe zfs

echo "[3/7] creating three 200M backing files..."
sudo mkdir -p "$STATE_DIR"
for i in 1 2 3; do
    sudo dd if=/dev/zero of="$STATE_DIR/disk$i.img" bs=1M count=200 status=none
done

echo "[4/7] attaching them as loop devices..."
: > /tmp/zfslab_loopdevs.$$
for i in 1 2 3; do
    LOOP=$(sudo losetup --find --show "$STATE_DIR/disk$i.img")
    echo "$LOOP" >> /tmp/zfslab_loopdevs.$$
done
sudo mv /tmp/zfslab_loopdevs.$$ "$STATE_DIR/loopdevs"
sudo chmod 644 "$STATE_DIR/loopdevs"
cat "$STATE_DIR/loopdevs"

echo "[5/7] creating raidz1 pool ($POOL) out of all three members..."
mapfile -t LOOPS < "$STATE_DIR/loopdevs"
sudo zpool create -f -m "$MNT" "$POOL" raidz1 "${LOOPS[0]}" "${LOOPS[1]}" "${LOOPS[2]}"
sudo chmod 777 "$MNT"

echo "[6/7] writing sample data..."
for i in $(seq 1 5); do
    sudo -u nobody dd if=/dev/urandom of="$MNT/baseline_$i" bs=1M count=5 status=none
done

echo "[7/7] taking the second member offline (simulating a failed drive)..."
sudo zpool offline "$POOL" "${LOOPS[1]}"

echo
echo "Done. Compare these:"
echo "  sudo zpool status $POOL   (pool should show DEGRADED)"
echo "  df -h $MNT                (still fully usable)"
echo
echo "To clean up later, see reset.sh."
