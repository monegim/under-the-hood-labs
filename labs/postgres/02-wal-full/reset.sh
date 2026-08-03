#!/usr/bin/env bash
# Lab 32 (WAL Full) reset — tears down the compose stack and the loop
# device/mount/backing file completely (setup.sh is not safe to re-run on
# top of an existing mount/loop device or a nearly-full WAL disk), then
# re-runs setup.sh to recreate the incident.
set -uo pipefail

cd "$(dirname "$0")"

echo "[reset] bringing compose stack down..."
docker compose down -v 2>/dev/null || true

echo "[reset] unmounting WAL disk if mounted..."
sudo umount ./data/wal-disk 2>/dev/null || true

if [ -f ./data/wal-disk.loopdev ]; then
  LOOPDEV=$(cat ./data/wal-disk.loopdev)
  echo "[reset] detaching loop device $LOOPDEV if attached..."
  sudo losetup -d "$LOOPDEV" 2>/dev/null || true
fi

echo "[reset] detaching any other loop devices still pointing at the WAL disk image..."
for dev in $(losetup -j ./data/wal-disk.img 2>/dev/null | cut -d: -f1); do
  sudo losetup -d "$dev" 2>/dev/null || true
done

echo "[reset] removing WAL disk image, mount point, and Postgres data dir..."
sudo rm -rf ./data

echo "[reset] re-running setup.sh to recreate the WAL-full incident..."
./setup.sh

echo "[reset] done. Run ./check.sh to verify health."
