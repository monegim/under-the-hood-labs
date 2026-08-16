#!/usr/bin/env bash
# Lab 13 reset — clears any leftover iptables rules from the challenges,
# kills the tail process, force/lazy-unmounts both the client mount and
# the server-side export, detaches all loop devices this lab created,
# removes lab state, and rebuilds via setup.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR=/var/lib/nfslab13
EXPORT=/srv/nfslab13
MNT=/mnt/nfslab13

echo "[reset] clearing any leftover NFS-port iptables rules..."
sudo iptables -D OUTPUT -p tcp --dport 2049 -j DROP 2>/dev/null || true
sudo iptables -D OUTPUT -p udp --dport 2049 -j DROP 2>/dev/null || true

echo "[reset] killing any leftover tail/cat processes against the mount..."
sudo pkill -f "tail -f $MNT" 2>/dev/null || true
sudo pkill -f "cat $MNT" 2>/dev/null || true

echo "[reset] unmounting client and export (force then lazy, in case something's stuck)..."
sudo umount -f "$MNT" 2>/dev/null || sudo umount -l "$MNT" 2>/dev/null || true
sudo umount -f "$EXPORT" 2>/dev/null || sudo umount -l "$EXPORT" 2>/dev/null || true

echo "[reset] removing the NFS export..."
sudo rm -f /etc/exports.d/nfslab13.exports 2>/dev/null || true
sudo exportfs -ra 2>/dev/null || true

echo "[reset] detaching any loop devices backed by this lab's images..."
for img in "$STATE_DIR"/disk*.img; do
    [ -f "$img" ] || continue
    for dev in $(losetup -j "$img" 2>/dev/null | cut -d: -f1); do
        sudo losetup -d "$dev" 2>/dev/null || true
    done
done

echo "[reset] removing lab state..."
sudo rm -rf "$STATE_DIR"

echo "[reset] rebuilding via setup.sh..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
