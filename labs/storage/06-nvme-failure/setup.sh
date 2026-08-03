#!/usr/bin/env bash
# Lab 6 setup — simulates a flapping/failing drive using the dm-flakey
# device-mapper target layered over a loop device: up for 20s, erroring
# for 10s, repeating. This is a SIMULATION - see README's "Honesty check"
# section. smartctl will not return real data against this device; only
# dmesg/writer.log reflect real, observable behavior.
set -euo pipefail

STATE_DIR=/var/lib/nvmelab
LOG_DIR=/var/log/nvmelab
MNT=/mnt/nvmedata
DMNAME=nvme0

echo "[1/6] installing smartmontools (for reference commands only) if missing..."
if ! command -v smartctl >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq smartmontools
fi

echo "[2/6] creating a 300M backing file..."
sudo mkdir -p "$STATE_DIR" "$LOG_DIR"
sudo dd if=/dev/zero of="$STATE_DIR/disk.img" bs=1M count=300 status=none

echo "[3/6] attaching it as a loop device..."
LOOPDEV=$(sudo losetup --find --show "$STATE_DIR/disk.img")
echo "$LOOPDEV" | sudo tee "$STATE_DIR/loopdev" > /dev/null
echo "      loop device: $LOOPDEV"

echo "[4/6] layering a dm-flakey device on top (up 20s, down/erroring 10s)..."
SIZE=$(sudo blockdev --getsz "$LOOPDEV")
sudo dmsetup create "$DMNAME" --table "0 $SIZE flakey $LOOPDEV 0 20 10"

echo "[5/6] formatting and mounting the flakey device..."
sudo mkfs.ext4 -q "/dev/mapper/$DMNAME"
sudo mkdir -p "$MNT"
sudo mount "/dev/mapper/$DMNAME" "$MNT"
sudo chmod 777 "$MNT"

echo "[6/6] starting the writer loop that logs every failed write..."
sudo tee "$STATE_DIR/writer.sh" > /dev/null <<'EOF'
#!/usr/bin/env bash
MNT=/mnt/nvmedata
LOG=/var/log/nvmelab/writer.log
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
echo "Done. This is a SIMULATED drive failure (dm-flakey over a loop"
echo "device) - see README's honesty check section."
echo
echo "Watch it flap:"
echo "  tail -f $LOG_DIR/writer.log"
echo "  dmesg -T | tail -40"
echo
echo "To clean up later, see reset.sh."
