#!/usr/bin/env bash
# Lab 15 setup — a loop-device-backed filesystem, throttled via cgroup
# io.max to behave like a modest, queue-depth-constrained disk (so
# scheduler choice actually has contention to arbitrate), with a
# background I/O hog and a latency-sensitive "foreground" writer both
# placed in the same throttled cgroup.
#
# HONESTY NOTE (read this): I/O scheduler effects are most pronounced on
# real rotational or genuinely queue-depth-limited hardware. A loop
# device backed by the host page cache is not that - this lab throttles
# it artificially via cgroup io.max specifically to create real,
# measurable contention, but the exact magnitude of difference between
# schedulers may vary by kernel version and is worth confirming live
# before recording, same as labs/storage/06-nvme-failure's simulation.
set -euo pipefail

STATE_DIR=/var/lib/ioschedlab15
LOG_DIR=/var/log/ioschedlab15
MNT=/mnt/ioschedlab15
CGROUP=/sys/fs/cgroup/ioschedlab15

echo "[1/8] installing fio and sysstat if missing..."
command -v fio >/dev/null 2>&1 || { sudo apt-get update -qq; sudo apt-get install -y -qq fio; }
command -v iostat >/dev/null 2>&1 || { sudo apt-get update -qq; sudo apt-get install -y -qq sysstat; }

echo "[2/8] cleaning up any previous run..."
sudo pkill -f "$STATE_DIR/sensitive.sh" 2>/dev/null || true
sudo pkill -f "fio --name=schedhog" 2>/dev/null || true
sleep 1
[ -d "$CGROUP" ] && { for p in $(cat "$CGROUP/cgroup.procs" 2>/dev/null); do sudo kill -9 "$p" 2>/dev/null || true; done; sudo rmdir "$CGROUP" 2>/dev/null || true; }
sudo umount "$MNT" 2>/dev/null || true
if [ -f "$STATE_DIR/loopdev" ]; then sudo losetup -d "$(cat "$STATE_DIR/loopdev")" 2>/dev/null || true; fi
sudo rm -rf "$STATE_DIR" "$LOG_DIR"
sudo mkdir -p "$STATE_DIR" "$LOG_DIR" "$MNT"

echo "[3/8] creating a 300M loop-device-backed filesystem..."
sudo dd if=/dev/zero of="$STATE_DIR/disk.img" bs=1M count=300 status=none
LOOPDEV=$(sudo losetup --find --show "$STATE_DIR/disk.img")
echo "$LOOPDEV" | sudo tee "$STATE_DIR/loopdev" > /dev/null
sudo mkfs.ext4 -q "$LOOPDEV"
sudo mount "$LOOPDEV" "$MNT"
sudo chmod 777 "$MNT"

echo "[4/8] checking available I/O schedulers for $LOOPDEV..."
DEVNAME=$(basename "$LOOPDEV")
SCHED_FILE="/sys/block/$DEVNAME/queue/scheduler"
if [ -f "$SCHED_FILE" ]; then
    echo "      available: $(cat "$SCHED_FILE")"
else
    echo "      WARNING: $SCHED_FILE doesn't exist on this kernel — scheduler switching won't work as written." >&2
fi
sudo modprobe bfq 2>/dev/null || true
echo "      after modprobe bfq: $(cat "$SCHED_FILE" 2>/dev/null || echo 'n/a')"

echo "[5/8] setting the scheduler to 'none' (the broken starting state for this lab)..."
if [ -f "$SCHED_FILE" ] && grep -q "none" "$SCHED_FILE"; then
    echo none | sudo tee "$SCHED_FILE" > /dev/null
fi
cat "$SCHED_FILE" 2>/dev/null || true

echo "[6/8] creating a throttled cgroup (this is what makes scheduler choice matter on a loop device)..."
sudo mkdir -p "$CGROUP"
MAJMIN=$(lsblk -ndo MAJ:MIN "$LOOPDEV")
echo "$MAJMIN rbps=2097152 wbps=2097152 riops=200 wiops=200" | sudo tee "$CGROUP/io.max" > /dev/null
echo "      throttled $LOOPDEV ($MAJMIN) to ~2MB/s, 200 IOPS for this cgroup"

echo "[7/8] writing the latency-sensitive 'foreground' writer..."
sudo tee "$STATE_DIR/sensitive.sh" > /dev/null <<EOF
#!/usr/bin/env bash
while true; do
    START=\$(date +%s%N)
    echo "tick" > "$MNT/sensitive.dat"
    sync "$MNT/sensitive.dat" 2>/dev/null || sync
    END=\$(date +%s%N)
    MS=\$(( (END - START) / 1000000 ))
    echo "\$(date '+%H:%M:%S') write_latency_ms=\$MS" >> "$LOG_DIR/sensitive.log"
    sleep 0.5
done
EOF
sudo chmod +x "$STATE_DIR/sensitive.sh"

echo "[8/8] starting both processes inside the throttled cgroup..."
sudo bash -c "
  echo \$\$ > $CGROUP/cgroup.procs
  exec nohup '$STATE_DIR/sensitive.sh' > /dev/null 2>&1 &
  echo \$! > $STATE_DIR/sensitive.pid
"
sudo bash -c "
  echo \$\$ > $CGROUP/cgroup.procs
  cd '$MNT' && exec nohup fio --name=schedhog --filename=hogfile --size=200M \
    --rw=randwrite --bs=4k --numjobs=2 --time_based --runtime=300 --direct=1 \
    --output='$LOG_DIR/fio.log' > /dev/null 2>&1 &
  echo \$! > $STATE_DIR/fio.pid
"

echo
echo "Done. Give it 10-15s, then compare foreground latency under contention:"
echo "  tail -20 $LOG_DIR/sensitive.log"
echo "  cat $SCHED_FILE"
