#!/usr/bin/env bash
# Lab 14 reset — kills the hog, cleans up the cgroup, swaps off and
# removes this lab's swapfile(s) specifically (never touches any
# pre-existing system swap), resets swappiness to the kernel default,
# and rebuilds via setup.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR=/var/lib/swaplab14
CGROUP=/sys/fs/cgroup/swaplab14

echo "[reset] killing the hog and anything else in the lab cgroup..."
sudo pkill -f "$STATE_DIR/hog.py" 2>/dev/null || true
sleep 1
if [ -d "$CGROUP" ]; then
    for p in $(cat "$CGROUP/cgroup.procs" 2>/dev/null); do sudo kill -9 "$p" 2>/dev/null || true; done
    sleep 1
    sudo rmdir "$CGROUP" 2>/dev/null || true
fi

echo "[reset] restoring default swappiness (60, the kernel default) in case Challenge B changed it..."
sudo sysctl -w vm.swappiness=60 >/dev/null

echo "[reset] swapping off and removing this lab's swapfile(s) specifically..."
for f in "$STATE_DIR"/swapfile "$STATE_DIR"/emergency-swap; do
    [ -f "$f" ] && sudo swapoff "$f" 2>/dev/null
done

echo "[reset] removing lab state..."
sudo rm -rf "$STATE_DIR"

echo "[reset] rebuilding via setup.sh..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
