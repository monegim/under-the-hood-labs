#!/usr/bin/env bash
# Lab 13 setup — a loopback NFS export (server and client both on this
# VM, matching the technique already used in linux/09) backed by a loop
# device. A client process keeps a file open across the mount. Nothing
# is broken yet — that happens live, in the README's own steps, so the
# reader watches "stale file handle" get produced on purpose rather than
# just being told about it.
set -euo pipefail

STATE_DIR=/var/lib/nfslab13
EXPORT=/srv/nfslab13
MNT=/mnt/nfslab13

echo "[1/7] installing nfs-kernel-server and nfs-common if missing..."
if ! command -v exportfs >/dev/null 2>&1 || ! command -v mount.nfs >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nfs-kernel-server nfs-common
fi

echo "[2/7] cleaning up any previous run..."
sudo umount -f "$MNT" 2>/dev/null || true
sudo umount -f "$EXPORT" 2>/dev/null || true
sudo pkill -f "tail -f $MNT" 2>/dev/null || true
sudo rm -f /etc/exports.d/nfslab13.exports 2>/dev/null || true
sudo exportfs -ra 2>/dev/null || true

echo "[3/7] creating a 200M loop-device-backed filesystem as the NFS export's backing store..."
sudo mkdir -p "$STATE_DIR" "$EXPORT" "$MNT"
sudo dd if=/dev/zero of="$STATE_DIR/disk.img" bs=1M count=200 status=none
LOOPDEV=$(sudo losetup --find --show "$STATE_DIR/disk.img")
echo "$LOOPDEV" | sudo tee "$STATE_DIR/loopdev" > /dev/null
sudo mkfs.ext4 -q "$LOOPDEV"
sudo mount "$LOOPDEV" "$EXPORT"
sudo chmod 777 "$EXPORT"
echo "hello from the original export" | sudo tee "$EXPORT/data.txt" > /dev/null

echo "[4/7] exporting it over NFS to localhost..."
echo "$EXPORT 127.0.0.1(rw,sync,no_subtree_check,no_root_squash)" | sudo tee /etc/exports.d/nfslab13.exports > /dev/null
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
sleep 2
showmount -e 127.0.0.1

echo "[5/7] mounting it as a client (default hard mount)..."
sudo mount -t nfs 127.0.0.1:"$EXPORT" "$MNT"
cat "$MNT/data.txt"

echo "[6/7] starting a client process that keeps a file open across the mount..."
sudo bash -c "nohup tail -f '$MNT/data.txt' > /dev/null 2>&1 & echo \$! > '$STATE_DIR/tail.pid'"

echo "[7/7] done."
echo
echo "Export:  $EXPORT (backed by $LOOPDEV)"
echo "Client mount: $MNT"
echo
echo "Everything is healthy right now. The README's own steps break it on purpose."
