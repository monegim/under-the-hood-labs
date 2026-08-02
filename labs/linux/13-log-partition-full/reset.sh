#!/usr/bin/env bash
# Lab 13 reset — kill any lingering flood processes/services, tear down the
# loop device and mount completely (setup.sh isn't safe to re-run on top of
# an existing mount), clean up learner-added logrotate config, then re-run
# setup.sh to refill the partition.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] killing any lingering flaky-app writer processes..."
sudo pkill -f 'flaky-app' 2>/dev/null || true

echo "[reset] stopping/removing the Challenge B journald crash-loop service, if present..."
sudo systemctl stop crashloop-demo 2>/dev/null || true
sudo systemctl disable crashloop-demo 2>/dev/null || true
sudo rm -f /etc/systemd/system/crashloop-demo.service
sudo systemctl daemon-reload
sudo systemctl reset-failed 2>/dev/null || true

echo "[reset] removing learner-added logrotate config for the lab, if present..."
sudo rm -f /etc/logrotate.d/myapp

echo "[reset] unmounting /var/log/myapp if mounted..."
sudo umount /var/log/myapp 2>/dev/null || true

if [ -f /var/lib/loglab/loopdev ]; then
    LOOPDEV=$(cat /var/lib/loglab/loopdev)
    echo "[reset] detaching loop device $LOOPDEV if attached..."
    sudo losetup -d "$LOOPDEV" 2>/dev/null || true
fi

echo "[reset] detaching any other loop devices still pointing at the lab's backing file..."
for dev in $(losetup -j /var/lib/loglab/disk.img 2>/dev/null | cut -d: -f1); do
    sudo losetup -d "$dev" 2>/dev/null || true
done

echo "[reset] removing lab state directory..."
sudo rm -rf /var/lib/loglab

echo "[reset] removing any second flaky-app script copy from Challenge A..."
sudo rm -f /usr/local/bin/flaky-app-2.sh

echo "[reset] re-running setup.sh to recreate the log-partition-full incident..."
sudo bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
