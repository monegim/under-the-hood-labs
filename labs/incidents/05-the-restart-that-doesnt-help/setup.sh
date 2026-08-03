#!/usr/bin/env bash
# Incident 05 setup - builds the entire broken environment:
#   - an NFS export/mount to localhost (same trick as
#     labs/linux/09-process-stuck-in-d-state - exporting to 127.0.0.1
#     keeps this reproducible on any single VM, no second host needed)
#   - upload-worker.service: a systemd-managed process that copies files
#     from a "pending" directory onto the NFS mount, standing in for a
#     real app writing user uploads to network storage
#   - a big pending file, already mid-copy by the time the NFS path gets
#     cut, so upload-worker's write is genuinely blocked in the kernel
#     (D state) before you ever look at it
#
# By the time this script finishes, the on-call has (per the page)
# already tried restarting upload-worker.service at least once - it
# didn't help, and that's the diagnostic clue.
set -euo pipefail

echo "[1/8] Installing NFS server/client tools..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nfs-kernel-server nfs-common iptables python3 >/dev/null

echo "[2/8] Exporting /srv/uploads to ourselves over NFS..."
sudo mkdir -p /srv/uploads
sudo chmod 777 /srv/uploads
if ! grep -q "^/srv/uploads " /etc/exports 2>/dev/null; then
    echo "/srv/uploads 127.0.0.1(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports >/dev/null
fi
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server

echo "[3/8] Mounting it as a HARD mount at /mnt/uploads (matches production - 'soft' silently corrupts data on timeout, so real upload paths use 'hard')..."
sudo mkdir -p /mnt/uploads
if ! mountpoint -q /mnt/uploads; then
    sudo mount -t nfs -o hard,intr 127.0.0.1:/srv/uploads /mnt/uploads
fi
sudo chmod 777 /mnt/uploads

echo "[4/8] Deploying the upload-worker script..."
sudo mkdir -p /var/lib/uploadlab/pending
sudo chmod 777 /var/lib/uploadlab/pending
sudo tee /usr/local/bin/upload-worker.py > /dev/null <<'PYEOF'
#!/usr/bin/env python3
"""
Polls /var/lib/uploadlab/pending for files and copies each one onto the
NFS-backed /mnt/uploads, chunk by chunk with an fsync per chunk - the
same shape of write loop a real "save this upload to network storage"
code path would use. Nothing here is buggy: if this hangs, it's because
the write()/fsync() syscalls themselves are blocked in the kernel, not
because of anything this script did wrong.
"""
import glob
import os
import time

PENDING_DIR = "/var/lib/uploadlab/pending"
UPLOAD_DIR = "/mnt/uploads"
CHUNK = 1024 * 1024

while True:
    for path in sorted(glob.glob(os.path.join(PENDING_DIR, "*"))):
        dest = os.path.join(UPLOAD_DIR, os.path.basename(path) + ".part")
        final = os.path.join(UPLOAD_DIR, os.path.basename(path))
        try:
            with open(path, "rb") as src, open(dest, "wb") as dst:
                while True:
                    chunk = src.read(CHUNK)
                    if not chunk:
                        break
                    dst.write(chunk)
                    dst.flush()
                    os.fsync(dst.fileno())
            os.rename(dest, final)
            os.remove(path)
        except FileNotFoundError:
            pass
    time.sleep(1)
PYEOF
sudo chmod +x /usr/local/bin/upload-worker.py

echo "[5/8] Installing the systemd unit..."
sudo tee /etc/systemd/system/upload-worker.service > /dev/null <<'EOF'
[Unit]
Description=Upload worker (Incident 05)
After=network.target remote-fs.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/upload-worker.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now upload-worker.service

echo "[6/8] Dropping a large pending upload (500MB) so the copy takes a while..."
sudo -u nobody dd if=/dev/zero of=/var/lib/uploadlab/pending/big-upload.bin bs=1M count=500 status=none 2>/dev/null \
    || dd if=/dev/zero of=/var/lib/uploadlab/pending/big-upload.bin bs=1M count=500 status=none

echo "[7/8] Waiting for upload-worker to start copying it..."
sleep 3

echo "[8/8] Cutting the NFS path mid-write - simulating a flaky storage backend..."
sudo iptables -A OUTPUT -p tcp --dport 2049 -j DROP
sudo iptables -A INPUT -p tcp --sport 2049 -j DROP

echo
echo "Done. The incident is already in progress (per the page, the on-call"
echo "already tried 'systemctl restart upload-worker' twice before paging"
echo "this out further - it didn't help, which is itself the clue)."
echo
echo "Try:"
echo "  systemctl status upload-worker.service"
echo "  ps -eo pid,ppid,stat,wchan:32,cmd | grep '[u]pload-worker.py'"
