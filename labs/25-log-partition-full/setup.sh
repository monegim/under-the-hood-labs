#!/usr/bin/env bash
# Lab 25 setup — fills a dedicated "log partition" from a runaway
# error-retry loop.
#
# Mechanism: a small loop-backed filesystem mounted at /var/log/myapp
# (standing in for a real dedicated log partition, common in production so
# a runaway app can't take out the whole root filesystem). A background
# script simulates an app stuck in a tight connection-retry loop, logging
# an error every 10ms with no rotation, until the partition fills.
#
# Using a dedicated small filesystem (300M) instead of the real /var/log
# keeps this safe/reversible on your VM — you're not at risk of actually
# filling your host's root partition.
set -euo pipefail

echo "[1/5] Creating a 300M backing file for the log partition..."
sudo mkdir -p /var/lib/loglab
sudo dd if=/dev/zero of=/var/lib/loglab/disk.img bs=1M count=300 status=none

echo "[2/5] Attaching as loop device and formatting..."
LOOPDEV=$(sudo losetup --find --show /var/lib/loglab/disk.img)
echo "$LOOPDEV" | sudo tee /var/lib/loglab/loopdev > /dev/null
sudo mkfs.ext4 -q "$LOOPDEV"

echo "[3/5] Mounting at /var/log/myapp..."
sudo mkdir -p /var/log/myapp
sudo mount "$LOOPDEV" /var/log/myapp

echo "[4/5] Installing the runaway app (tight error-retry loop, no rotation)..."
# No sleep, and no per-line `date` fork/exec (that would throttle this to a
# crawl) - keeps one fd open and uses bash's built-in printf %()T so the
# loop is disk-bound, not fork-bound. This is what a genuinely crash-looping
# process logging as fast as it can looks like.
sudo tee /usr/local/bin/flaky-app.sh > /dev/null <<'EOF'
#!/usr/bin/env bash
exec 3>>/var/log/myapp/error.log
while true; do
    printf '%(%Y-%m-%d %H:%M:%S)T ERROR: upstream connection refused, retrying...\n' -1 >&3
done
EOF
sudo chmod +x /usr/local/bin/flaky-app.sh

echo "[5/5] Starting it in the background..."
nohup /usr/local/bin/flaky-app.sh > /tmp/flaky-app.log 2>&1 &
echo "      PID: $!"
disown

echo
echo "Done. This fills fast (no throttling) - give it 15-30 seconds, then check:"
echo "  df -h /var/log/myapp"
echo "  du -sh /var/log/myapp/*"
echo
echo "To stop the flood manually: sudo pkill -f flaky-app.sh"
