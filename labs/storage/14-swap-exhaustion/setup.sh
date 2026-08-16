#!/usr/bin/env bash
# Lab 14 setup — creates a small, DEDICATED 64M swapfile (on top of
# whatever swap the VM already has, if any — this lab never touches
# pre-existing swap) and a cgroup with memory.max set comfortably above
# what a normal process needs but tight enough that a hog's allocations
# push hard into swap. The swapfile is deliberately undersized so it's
# realistic to fill it completely without needing an enormous amount of
# memory pressure.
set -euo pipefail

STATE_DIR=/var/lib/swaplab14
SWAPFILE="$STATE_DIR/swapfile"
CGROUP=/sys/fs/cgroup/swaplab14

echo "[1/6] checking cgroup v2 is available..."
if [ "$(stat -fc %T /sys/fs/cgroup 2>/dev/null)" != "cgroup2fs" ]; then
    echo "ERROR: this lab needs cgroup v2 (unified hierarchy) at /sys/fs/cgroup." >&2
    exit 1
fi

echo "[2/6] cleaning up any previous run..."
sudo pkill -f "$STATE_DIR/hog.py" 2>/dev/null || true
sleep 1
if [ -d "$CGROUP" ]; then
    for p in $(cat "$CGROUP/cgroup.procs" 2>/dev/null); do sudo kill -9 "$p" 2>/dev/null || true; done
    sudo rmdir "$CGROUP" 2>/dev/null || true
fi
sudo swapoff "$SWAPFILE" 2>/dev/null || true
sudo rm -rf "$STATE_DIR"
sudo mkdir -p "$STATE_DIR"

echo "[3/6] creating a dedicated 64M swapfile (NOT touching any existing system swap)..."
sudo fallocate -l 64M "$SWAPFILE" 2>/dev/null || sudo dd if=/dev/zero of="$SWAPFILE" bs=1M count=64 status=none
sudo chmod 600 "$SWAPFILE"
sudo mkswap "$SWAPFILE" >/dev/null
sudo swapon "$SWAPFILE"
echo "      swap now:"
swapon --show

echo "[4/6] creating a cgroup with memory.max=200M (swap left unlimited for this cgroup)..."
sudo mkdir -p "$CGROUP"
echo "200M" | sudo tee "$CGROUP/memory.max" > /dev/null
echo "max" | sudo tee "$CGROUP/memory.swap.max" > /dev/null 2>&1 || true

echo "[5/6] writing the memory hog..."
sudo tee "$STATE_DIR/hog.py" > /dev/null <<'EOF'
import time
chunks = []
mb = 0
while True:
    chunks.append(bytearray(1024 * 1024))  # touch a fresh MB
    for b in chunks[-1]:
        pass
    mb += 1
    print(f"[hog] allocated ~{mb}MB", flush=True)
    time.sleep(0.3)
EOF

echo "[6/6] starting the hog inside the cgroup..."
sudo bash -c "
  echo \$\$ > $CGROUP/cgroup.procs
  exec nohup python3 $STATE_DIR/hog.py > $STATE_DIR/hog.log 2>&1 &
  echo \$! > $STATE_DIR/hog.pid
"

echo
echo "Done. Watch swap fill up over the next ~20-30 seconds:"
echo "  watch -n1 'free -h; echo; swapon --show; echo; cat /proc/swaps'"
echo "  tail -f $STATE_DIR/hog.log"
