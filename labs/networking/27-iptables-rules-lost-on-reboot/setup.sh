#!/usr/bin/env bash
set -euo pipefail

# Lab 27 setup: applies a real, working iptables rule live (blocking a
# test port), confirms it works — then simulates a reboot the honest
# way, the same way linux/12's "service won't start after reboot" lab
# avoids requiring a literal reboot: nothing loads saved rules at boot
# unless something is explicitly configured to, so a full `iptables -F`
# is exactly what the kernel's netfilter tables look like at the next
# boot if nothing persists them. This lab deliberately does NOT install
# netfilter-persistent up front — that gap is the incident.

STATE_DIR=/var/lib/iptableslab27
sudo mkdir -p "$STATE_DIR"

echo "[1/5] installing iptables if missing (netfilter-persistent deliberately NOT installed yet)..."
command -v iptables >/dev/null 2>&1 || { sudo apt-get update -qq; sudo apt-get install -y -qq iptables; }
sudo apt-get remove -y -qq iptables-persistent netfilter-persistent 2>/dev/null || true

echo "[2/5] starting a test listener on port 9999..."
sudo pkill -f "nc -lk 9999" 2>/dev/null || true
sleep 1
sudo bash -c 'nohup nc -lk 9999 </dev/null >/dev/null 2>&1 &'
sleep 1

echo "[3/5] clearing any leftover rules from a previous run..."
sudo iptables -F INPUT

echo "[4/5] applying the real, live fix: block port 9999 from everywhere..."
sudo iptables -A INPUT -p tcp --dport 9999 -j DROP

echo "[5/5] confirming it actually blocks right now..."
if timeout 3 bash -c 'echo hi | nc -w2 127.0.0.1 9999' >/dev/null 2>&1; then
    echo "      WARNING: connection succeeded — rule isn't blocking as expected." >&2
else
    echo "      confirmed: port 9999 is blocked."
fi

echo
echo "Done. The rule is live and working right now — but nothing has"
echo "persisted it. Simulate a reboot per the README's own steps."
