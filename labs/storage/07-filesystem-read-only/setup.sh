#!/usr/bin/env bash
# Lab 7 setup — triggers a real ext4 auto-remount-to-read-only event
# using a dm-flakey device layered over a loop device. The filesystem's
# error policy is explicitly set to remount-ro (tune2fs -e) so this is
# deterministic rather than relying on the distro's default.
set -euo pipefail

STATE_DIR=/var/lib/rolab
LOG_DIR=/var/log/rolab
MNT=/mnt/rodata
DMNAME=rofs0

echo "[1/6] installing e2fsprogs/xfsprogs/dmsetup if missing..."
if ! command -v mkfs.ext4 >/dev/null 2>&1 || ! command -v mkfs.xfs >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq e2fsprogs xfsprogs
fi

echo "[2/6] creating a 200M backing file..."
sudo mkdir -p "$STATE_DIR" "$LOG_DIR"
sudo dd if=/dev/zero of="$STATE_DIR/disk.img" bs=1M count=200 status=none

echo "[3/6] attaching it as a loop device..."
LOOPDEV=$(sudo losetup --find --show "$STATE_DIR/disk.img")
echo "$LOOPDEV" | sudo tee "$STATE_DIR/loopdev" > /dev/null
echo "      loop device: $LOOPDEV"

echo "[4/6] layering a dm-flakey device on top (up 15s, down/erroring 15s)..."
SIZE=$(sudo blockdev --getsz "$LOOPDEV")
sudo dmsetup create "$DMNAME" --table "0 $SIZE flakey $LOOPDEV 0 15 15"

echo "[5/6] formatting ext4 and explicitly setting the error policy to"
echo "      remount-ro (don't rely on the distro default)..."
sudo mkfs.ext4 -q "/dev/mapper/$DMNAME"
sudo tune2fs -e remount-ro "/dev/mapper/$DMNAME"
sudo mkdir -p "$MNT"
sudo mount "/dev/mapper/$DMNAME" "$MNT"
sudo chmod 777 "$MNT"
for i in $(seq 1 5); do
    sudo -u nobody dd if=/dev/urandom of="$MNT/app_data_$i" bs=4k count=4 status=none
done

echo "[6/6] starting the writer loop that logs every write attempt..."
sudo tee "$STATE_DIR/writer.sh" > /dev/null <<'EOF'
#!/usr/bin/env bash
MNT=/mnt/rodata
LOG=/var/log/rolab/writer.log
while true; do
    if echo "tick" > "$MNT/heartbeat" 2>>"$LOG"; then
        echo "$(date '+%H:%M:%S') write OK" >> "$LOG"
    else
        echo "$(date '+%H:%M:%S') write FAILED" >> "$LOG"
    fi
    sleep 1
done
EOF
sudo chmod +x "$STATE_DIR/writer.sh"
sudo bash -c "nohup '$STATE_DIR/writer.sh' >/dev/null 2>&1 & echo \$! > '$STATE_DIR/writer.pid'"

echo
echo "Done. Watch for the auto-remount-ro event:"
echo "  tail -f $LOG_DIR/writer.log"
echo "  dmesg -T | tail -20"
echo "  mount | grep rodata"
echo
echo "To clean up later, see reset.sh."
