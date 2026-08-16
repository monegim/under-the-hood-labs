#!/usr/bin/env bash
set -uo pipefail

# Lab 27 reset - kills the test listener, flushes INPUT, removes any
# persisted rules/backups this lab created, disables/removes
# netfilter-persistent (so the "not installed yet" starting state is
# genuinely reproduced), and rebuilds via setup.sh.

echo "[reset] killing the test listener..."
sudo pkill -f "nc -lk 9999" 2>/dev/null || true

echo "[reset] flushing INPUT..."
sudo iptables -F INPUT 2>/dev/null || true

echo "[reset] removing any persisted rules/backups this lab created..."
sudo rm -f /etc/iptables/rules.v4 /root/my-firewall-backup.txt

echo "[reset] disabling and removing netfilter-persistent (reproducing the 'not set up yet' starting state)..."
sudo systemctl disable --now netfilter-persistent 2>/dev/null || true
sudo apt-get remove -y -qq iptables-persistent netfilter-persistent 2>/dev/null || true

echo "[reset] removing lab state..."
sudo rm -rf /var/lib/iptableslab27

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[reset] rebuilding via setup.sh..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
