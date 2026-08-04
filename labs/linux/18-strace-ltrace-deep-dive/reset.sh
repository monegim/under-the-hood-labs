#!/usr/bin/env bash
# Lab 18 reset — tear down the main incident AND any challenge state
# (authcheck's env override, the producer/consumer FIFO units), then
# re-run setup.sh to reproduce the main configapp incident.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] stopping configapp.service..."
sudo systemctl stop configapp 2>/dev/null || true
sudo rm -rf /etc/systemd/system/configapp.service.d

echo "[reset] stopping/removing Challenge A (authcheck) state, if present..."
sudo systemctl stop configapp-authcheck.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/configapp-authcheck.service
sudo rm -rf /etc/systemd/system/configapp-authcheck.service.d

echo "[reset] stopping/removing Challenge B (producer/consumer FIFO) state, if present..."
sudo systemctl stop configapp-consumer.service 2>/dev/null || true
sudo systemctl stop configapp-producer.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/configapp-consumer.service
sudo rm -f /etc/systemd/system/configapp-producer.service
sudo rm -f /run/configapp/eventpipe

echo "[reset] reloading systemd and clearing failed-unit state..."
sudo systemctl daemon-reload
sudo systemctl reset-failed 2>/dev/null || true

echo "[reset] re-running setup.sh to rebuild the main configapp incident..."
sudo bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
