#!/usr/bin/env bash
# Lab 8 setup — builds an LVM "snapshot ran out of COW space and went
# Invalid" incident: a 600M volume group on a single loop device, a 200M
# ext4 origin LV with sample data, a deliberately undersized 20M snapshot,
# then enough churn on the origin to exhaust the snapshot's COW space and
# invalidate it before the lab even starts.
#
# Using a loop device for the VG keeps this safe and reversible: no real
# disks are touched, and teardown is unmount + vgremove/pvremove +
# losetup -d.
set -euo pipefail

STATE_DIR=/var/lib/lvmsnaplab
VG=snapvg
ORIGIN=origin
MNT=/mnt/snaporigin

echo "[1/7] installing lvm2 if missing..."
if ! command -v pvcreate >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq lvm2
fi

echo "[2/7] creating a 600M backing file for the VG..."
sudo mkdir -p "$STATE_DIR"
sudo dd if=/dev/zero of="$STATE_DIR/disk.img" bs=1M count=600 status=none

echo "[3/7] attaching it as a loop device..."
LOOPDEV=$(sudo losetup --find --show "$STATE_DIR/disk.img")
echo "$LOOPDEV" | sudo tee "$STATE_DIR/loopdev" > /dev/null
echo "      loop device: $LOOPDEV"

echo "[4/7] creating volume group $VG..."
sudo pvcreate -f "$LOOPDEV"
sudo vgcreate "$VG" "$LOOPDEV"

echo "[5/7] creating a 200M ext4 origin LV ($ORIGIN) with sample data..."
sudo lvcreate -L 200M -n "$ORIGIN" "$VG"
sudo mkfs.ext4 -q "/dev/$VG/$ORIGIN"
sudo mkdir -p "$MNT"
sudo mount "/dev/$VG/$ORIGIN" "$MNT"
sudo chmod 777 "$MNT"
for i in $(seq 1 5); do
    sudo -u nobody dd if=/dev/urandom of="$MNT/baseline_$i" bs=1M count=10 status=none
done

echo "[6/7] taking a deliberately undersized 20M snapshot (snap1)..."
sudo lvcreate -s -L 20M -n snap1 "/dev/$VG/$ORIGIN"

echo "[7/7] churning the origin well past what a 20M snapshot can absorb..."
set +e
for i in $(seq 1 5); do
    sudo -u nobody dd if=/dev/urandom of="$MNT/baseline_$i" bs=1M count=10 conv=notrunc status=none
done
set -e

echo
echo "Done. Compare these:"
echo "  sudo lvs -a -o+snap_percent,lv_attr $VG   (snap1 should show Invalid)"
echo "  df -h $MNT                                (origin itself is fine)"
echo
echo "To clean up later, see reset.sh."
