#!/usr/bin/env bash
# Lab 21 setup — builds a real D-state (uninterruptible sleep) process.
#
# Mechanism: loopback NFS mount + iptables DROP on the NFS port.
#   1. Export a directory over NFS to localhost.
#   2. Mount it with `hard` (the default) — a hard mount means the kernel
#      NFS client retries forever and never returns an error to the calling
#      process, it just blocks.
#   3. Start a process writing to a file on that mount.
#   4. DROP (not REJECT) outbound traffic to the NFS port. DROP causes
#      packets to vanish silently, so the client's TCP stack just retransmits
#      and waits — this is what puts the write() syscall into
#      TASK_UNINTERRUPTIBLE (D state): the kernel is waiting on the network
#      block layer for a response that will never come, and refuses to be
#      interrupted mid-syscall because that could corrupt in-flight I/O state.
#
# This is the same mechanism (NFS server unreachable) behind real-world
# "df hangs", "ls hangs", "can't kill -9 this process" incidents on any box
# with NFS mounts. It reproduces reliably because it only depends on
# standard nfs-kernel-server + iptables, not on any specific VM's disk
# hardware.
set -euo pipefail

echo "[1/6] Installing nfs-kernel-server and nfs-common..."
sudo apt-get update -qq
sudo apt-get install -y -qq nfs-kernel-server nfs-common iptables > /dev/null

echo "[2/6] Creating export directory..."
sudo mkdir -p /srv/nfslab
sudo chmod 777 /srv/nfslab

echo "[3/6] Configuring NFS export for localhost..."
if ! grep -q "/srv/nfslab" /etc/exports 2>/dev/null; then
    echo "/srv/nfslab 127.0.0.1(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports > /dev/null
fi
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
sleep 2

echo "[4/6] Mounting it locally (hard mount — this is the point)..."
sudo mkdir -p /mnt/nfslab
if ! mountpoint -q /mnt/nfslab; then
    sudo mount -t nfs -o hard,timeo=600 127.0.0.1:/srv/nfslab /mnt/nfslab
fi

echo "[5/6] Starting a background writer against the NFS mount..."
nohup dd if=/dev/zero of=/mnt/nfslab/testfile bs=1M count=2000 > /tmp/dd-nfslab.log 2>&1 &
DD_PID=$!
disown
echo "      dd PID: $DD_PID"
sleep 1

echo "[6/6] Cutting off the NFS server (DROP, not REJECT) to freeze the write mid-flight..."
sudo iptables -A OUTPUT -p tcp --dport 2049 -j DROP
sudo iptables -A INPUT -p tcp --sport 2049 -j DROP

sleep 2
echo
echo "Done. dd (PID $DD_PID) should now be stuck."
echo
echo "Verify with:"
echo "  ps -o pid,stat,cmd -p $DD_PID"
echo "  cat /proc/$DD_PID/status | grep State"
echo
echo "To restore (unblocks the hung dd):"
echo "  sudo iptables -D OUTPUT -p tcp --dport 2049 -j DROP"
echo "  sudo iptables -D INPUT -p tcp --sport 2049 -j DROP"
