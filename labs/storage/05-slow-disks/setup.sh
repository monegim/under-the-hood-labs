#!/usr/bin/env bash
# Lab 5 setup — builds a disk-I/O-contention incident: a small "victim"
# service writing+fsyncing a file in a loop and logging its own latency,
# starved by a competing fio I/O hog on the same loop-device-backed
# filesystem.
#
# Using a dedicated loop device for the target filesystem keeps this
# isolated from the VM's real disks - the hog only ever writes into
# /mnt/slowdata, backed by a throwaway image file.
set -euo pipefail

STATE_DIR=/var/lib/slowlab
LOG_DIR=/var/log/slowlab
MNT=/mnt/slowdata

echo "[1/6] installing sysstat and fio if missing..."
if ! command -v iostat >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq sysstat
fi
if ! command -v fio >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq fio
fi

echo "[2/6] creating a 300M backing file and mounting it..."
sudo mkdir -p "$STATE_DIR" "$LOG_DIR"
sudo dd if=/dev/zero of="$STATE_DIR/disk.img" bs=1M count=300 status=none
LOOPDEV=$(sudo losetup --find --show "$STATE_DIR/disk.img")
echo "$LOOPDEV" | sudo tee "$STATE_DIR/loopdev" > /dev/null
sudo mkfs.ext4 -q "$LOOPDEV"
sudo mkdir -p "$MNT"
sudo mount "$LOOPDEV" "$MNT"
sudo chmod 777 "$MNT"

echo "[3/6] writing the victim service script..."
sudo tee "$STATE_DIR/victim.sh" > /dev/null <<'EOF'
#!/usr/bin/env bash
MNT=/mnt/slowdata
LOG=/var/log/slowlab/service.log
while true; do
    START=$(date +%s%N)
    echo "tick" > "$MNT/victim.dat"
    sync "$MNT/victim.dat" 2>/dev/null || sync
    END=$(date +%s%N)
    MS=$(( (END - START) / 1000000 ))
    echo "$(date '+%H:%M:%S') write_latency_ms=$MS" >> "$LOG"
    sleep 0.5
done
EOF
sudo chmod +x "$STATE_DIR/victim.sh"

echo "[4/6] starting the victim service in the background..."
sudo bash -c "nohup '$STATE_DIR/victim.sh' >/dev/null 2>&1 & echo \$! > '$STATE_DIR/victim.pid'"

echo "[5/6] letting it record a healthy baseline (10s)..."
sleep 10
echo "      baseline:"
tail -5 "$LOG_DIR/service.log"

echo "[6/6] starting the competing fio I/O hog..."
sudo bash -c "cd '$MNT' && nohup fio --name=hog --filename=hogfile --size=250M \
  --rw=randwrite --bs=4k --numjobs=4 --time_based --runtime=300 --direct=1 \
  --output='$LOG_DIR/fio.log' >/dev/null 2>&1 & echo \$! > '$STATE_DIR/fio.pid'"

echo
echo "Done. Give it ~10-15s for the hog to ramp up, then check:"
echo "  tail -20 $LOG_DIR/service.log"
echo "  iostat -x 1 5"
echo "  vmstat 1 5"
echo
echo "To clean up later, see reset.sh."
