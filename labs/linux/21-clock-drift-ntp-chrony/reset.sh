#!/usr/bin/env bash
# Lab 21 reset — undo any challenge state (bad chrony server config,
# iptables NTP block), FORCE the clock back to correct time first (most
# important step - do not leave a VM's clock skewed), then re-run
# setup.sh to reproduce the main incident.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] removing any NTP-port iptables block from Challenge B..."
sudo iptables -D OUTPUT -p udp --dport 123 -j DROP 2>/dev/null || true

echo "[reset] restoring the real chrony.conf (removing Challenge A's bad server), if a backup exists..."
if [ -f /etc/chrony/chrony.conf.lab21.bak ]; then
    sudo cp /etc/chrony/chrony.conf.lab21.bak /etc/chrony/chrony.conf
fi

echo "[reset] unmasking and starting chrony, forcing an immediate clock step..."
sudo systemctl unmask chrony 2>/dev/null || true
sudo timedatectl set-ntp true
sudo systemctl restart chrony
sleep 2
sudo chronyc makestep 2>/dev/null || true
sleep 2
date

echo "[reset] killing the test HTTPS endpoint..."
sudo pkill -f "openssl s_server" 2>/dev/null || true

echo "[reset] clock restored. Re-running setup.sh to rebuild the incident..."
sudo bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
