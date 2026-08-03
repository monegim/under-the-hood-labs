#!/usr/bin/env bash
# Lab 4 setup — builds a healthy 3-member RAID5 array on loop devices,
# formatted with ext4 and mounted with sample data, as the starting point
# for failing/rebuilding a member.
#
# Using loop devices for the RAID members keeps this safe and reversible:
# no real disks are touched, and teardown is stop + zero-superblock +
# losetup -d.
set -euo pipefail

STATE_DIR=/var/lib/raidlab
MNT=/mnt/raiddata
MD=/dev/md0

echo "[1/6] installing mdadm if missing..."
if ! command -v mdadm >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq mdadm
fi

echo "[2/6] creating three 150M backing files for RAID members..."
sudo mkdir -p "$STATE_DIR"
for i in 1 2 3; do
    sudo dd if=/dev/zero of="$STATE_DIR/disk$i.img" bs=1M count=150 status=none
done

echo "[3/6] attaching them as loop devices..."
: > /tmp/raidlab_loopdevs.$$
for i in 1 2 3; do
    LOOP=$(sudo losetup --find --show "$STATE_DIR/disk$i.img")
    echo "$LOOP" >> /tmp/raidlab_loopdevs.$$
done
sudo mv /tmp/raidlab_loopdevs.$$ "$STATE_DIR/loopdevs"
sudo chmod 644 "$STATE_DIR/loopdevs"
cat "$STATE_DIR/loopdevs"

echo "[4/6] creating RAID5 array md0 out of all three members..."
mapfile -t LOOPS < "$STATE_DIR/loopdevs"
sudo mdadm --create "$MD" --run --level=5 --raid-devices=3 --metadata=1.2 \
    "${LOOPS[0]}" "${LOOPS[1]}" "${LOOPS[2]}"

echo "[5/6] waiting for the initial sync to finish..."
while grep -q resync /proc/mdstat 2>/dev/null; do
    sleep 1
done
sudo mdadm --detail "$MD"

echo "[6/6] formatting with ext4 and writing sample data..."
sudo mkfs.ext4 -q "$MD"
sudo mkdir -p "$MNT"
sudo mount "$MD" "$MNT"
sudo chmod 777 "$MNT"
for i in $(seq 1 10); do
    sudo -u nobody dd if=/dev/urandom of="$MNT/app_data_$i" bs=4k count=4 status=none
done

echo
echo "Done. Array members (in order):"
cat -n "$STATE_DIR/loopdevs"
echo
echo "Try:"
echo "  sudo mdadm --detail $MD"
echo "  cat /proc/mdstat"
echo
echo "To clean up later, see reset.sh."
