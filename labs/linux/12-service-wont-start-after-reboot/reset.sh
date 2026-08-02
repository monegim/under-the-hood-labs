#!/usr/bin/env bash
# Lab 12 reset — undo the fix/challenge state (webapp override, masked mysql,
# bad fstab line), then re-run setup.sh's failure sequence: stop mysql,
# start webapp with no After=/Requires= between them.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] stopping webapp.service..."
sudo systemctl stop webapp 2>/dev/null || true

echo "[reset] removing any webapp.service.d override (Step 5 fix / Challenge A)..."
sudo rm -rf /etc/systemd/system/webapp.service.d

echo "[reset] unmasking mysql.service in case Challenge A masked it..."
sudo systemctl unmask mysql.service 2>/dev/null || true

echo "[reset] removing the bad fstab entry from Challenge B, if present..."
sudo sed -i '/thisdoesnotexist/d' /etc/fstab

echo "[reset] reloading systemd and clearing failed-unit state..."
sudo systemctl daemon-reload
sudo systemctl reset-failed 2>/dev/null || true

echo "[reset] re-running setup.sh to rebuild webapp.service and reproduce the race (stop mysql, start webapp)..."
sudo bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
