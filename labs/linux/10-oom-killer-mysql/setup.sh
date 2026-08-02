#!/usr/bin/env bash
# Lab 22 setup — triggers the OOM killer against mysqld.
#
# Mechanism: instead of resizing the whole VM's RAM (risky, and results vary
# by host), we cap memory with a systemd/cgroup v2 slice so the trigger is
# reliable regardless of how much RAM your VM actually has:
#   1. Create a slice `oom-lab.slice` with MemoryMax set low.
#   2. Move mysql.service into that slice (its memory now counts against
#      the slice's limit, not the whole machine's).
#   3. Set innodb_buffer_pool_size deliberately too high for the slice.
#   4. Run a memory-hungry sibling (stress-ng) in the SAME slice, so combined
#      usage crosses MemoryMax.
#   5. The kernel's cgroup-aware OOM killer picks a victim inside the slice
#      by badness score — mysqld's large RSS (driven by the oversized buffer
#      pool) makes it the likely target.
#
# NOTE: this assumes cgroup v2 unified hierarchy (default on Ubuntu 20.04+
# with systemd). Check with: `stat -fc %T /sys/fs/cgroup/` -> should print
# "cgroup2fs". If your VM is on cgroup v1, MemoryMax property mapping still
# generally works via systemd's compat layer, but is less predictable.
set -euo pipefail

echo "[1/6] Installing mysql-server and stress-ng..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mysql-server stress-ng > /dev/null

echo "[2/6] Creating a memory-capped slice (oom-lab.slice, MemoryMax=1200M)..."
sudo mkdir -p /etc/systemd/system/oom-lab.slice.d
sudo tee /etc/systemd/system/oom-lab.slice.d/override.conf > /dev/null <<'EOF'
[Slice]
MemoryMax=1200M
MemorySwapMax=0
EOF
sudo systemctl daemon-reload

echo "[3/6] Moving mysql.service into oom-lab.slice..."
sudo mkdir -p /etc/systemd/system/mysql.service.d
sudo tee /etc/systemd/system/mysql.service.d/override.conf > /dev/null <<'EOF'
[Service]
Slice=oom-lab.slice
EOF

echo "[4/6] Setting innodb_buffer_pool_size too high for this slice (900M)..."
sudo tee /etc/mysql/mysql.conf.d/zzz-lab22.cnf > /dev/null <<'EOF'
[mysqld]
innodb_buffer_pool_size=900M
EOF

echo "[5/6] Restarting mysqld inside the capped slice..."
sudo systemctl daemon-reload
sudo systemctl restart mysql
sleep 3
systemctl status mysql --no-pager -l | head -5

echo "[6/6] Squeezing it with a memory-hungry sibling in the same slice..."
sudo systemd-run --unit=oom-lab-hog --slice=oom-lab.slice \
    stress-ng --vm 1 --vm-bytes 500M --vm-keep --timeout 60s

echo
echo "Done. Watch for the kill:"
echo "  sudo dmesg -T | grep -i -E 'oom|killed process'"
echo "  journalctl -k --since '2 min ago' | grep -i oom"
echo "  systemctl status mysql"
echo
echo "If mysqld does NOT get killed within ~60s, the slice limit is too"
echo "generous for your VM's overhead — lower MemoryMax in"
echo "/etc/systemd/system/oom-lab.slice.d/override.conf, daemon-reload, and rerun."
