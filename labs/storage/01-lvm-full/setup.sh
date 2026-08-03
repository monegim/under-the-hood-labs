#!/usr/bin/env bash
# Lab 1 setup — builds an LVM "filesystem full, but the VG has room"
# incident: a 500M volume group (two 250M loop-backed PVs) with a 60M
# ext4 LV mounted at /mnt/appdata, filled until writes fail.
#
# Using loop devices for the PVs keeps this safe and reversible: no real
# disks or partitions are touched, and teardown is just unmount +
# lvremove/vgremove/pvremove + losetup -d.
set -euo pipefail

STATE_DIR=/var/lib/lvmlab
VG=labvg
LV=lvapp
MNT=/mnt/appdata

echo "[1/6] installing lvm2 if missing..."
if ! command -v pvcreate >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq lvm2
fi

echo "[2/6] creating two 250M backing files for the VG's PVs..."
sudo mkdir -p "$STATE_DIR"
sudo dd if=/dev/zero of="$STATE_DIR/disk1.img" bs=1M count=250 status=none
sudo dd if=/dev/zero of="$STATE_DIR/disk2.img" bs=1M count=250 status=none

echo "[3/6] attaching them as loop devices..."
LOOP1=$(sudo losetup --find --show "$STATE_DIR/disk1.img")
LOOP2=$(sudo losetup --find --show "$STATE_DIR/disk2.img")
echo "$LOOP1" | sudo tee "$STATE_DIR/loop1" > /dev/null
echo "$LOOP2" | sudo tee "$STATE_DIR/loop2" > /dev/null
echo "      $LOOP1 $LOOP2"

echo "[4/6] building a 500M volume group ($VG) out of both..."
sudo pvcreate -f "$LOOP1" "$LOOP2"
sudo vgcreate "$VG" "$LOOP1" "$LOOP2"

echo "[5/6] creating a deliberately small 60M LV ($LV) - most of the VG"
echo "      stays unallocated on purpose..."
sudo lvcreate -L 60M -n "$LV" "$VG"
sudo mkfs.ext4 -q "/dev/$VG/$LV"
sudo mkdir -p "$MNT"
sudo mount "/dev/$VG/$LV" "$MNT"
sudo chmod 777 "$MNT"

echo "[6/6] simulating the app filling its 60M volume..."
set +e
sudo -u nobody dd if=/dev/zero of="$MNT/filler" bs=1M count=100 status=none 2>/dev/null
set -e

echo
echo "Done. Compare these:"
echo "  df -h $MNT          (filesystem layer - looks full)"
echo "  sudo lvs $VG        (LV layer - 60M, fully used)"
echo "  sudo vgs $VG        (VG layer - lots of VFree left)"
echo
echo "To clean up later, see reset.sh."
