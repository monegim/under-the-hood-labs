#!/usr/bin/env bash
# Lab 6 reset — tear down both loop-mounted filesystems completely (not
# safe to re-run setup.sh on top of an existing mount), then re-run
# setup.sh to recreate the binlog disk-full incident.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] stopping mysql..."
sudo systemctl stop mysql 2>/dev/null || true

echo "[reset] unmounting /mnt/mysql-binlogs and /mnt/mysql-tmp if mounted..."
sudo umount /mnt/mysql-binlogs 2>/dev/null || true
sudo umount /mnt/mysql-tmp 2>/dev/null || true

for f in /var/lib/mysqllab06/binlog-loopdev /var/lib/mysqllab06/tmp-loopdev; do
  if [ -f "$f" ]; then
    DEV=$(cat "$f")
    echo "[reset] detaching loop device $DEV if attached..."
    sudo losetup -d "$DEV" 2>/dev/null || true
  fi
done

echo "[reset] detaching any other loop devices still pointing at the lab's backing files..."
for img in /var/lib/mysqllab06/binlogs.img /var/lib/mysqllab06/tmp.img; do
  for dev in $(losetup -j "$img" 2>/dev/null | cut -d: -f1); do
    sudo losetup -d "$dev" 2>/dev/null || true
  done
done

echo "[reset] removing lab state directory and lab config..."
sudo rm -rf /var/lib/mysqllab06
sudo rm -f /etc/mysql/mysql.conf.d/zzz-lab06.cnf

echo "[reset] re-running setup.sh to recreate the incident..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
