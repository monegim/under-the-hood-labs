#!/usr/bin/env bash
# Lab 21 setup — builds a real clock-drift incident: chronyd stopped and
# masked, NTP sync disabled, and the system clock jumped 60 days into the
# future. This makes a perfectly valid TLS certificate appear "expired" -
# the classic "unrelated-looking symptom" of clock drift.
#
# CAUTION: this changes the VM's whole-system clock, not just something in
# a sandboxed directory (unlike most other labs in this series). Run this
# on a disposable/test VM, not a shared or production box.
set -euo pipefail

echo "[1/6] Installing chrony and openssl (if missing)..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq chrony openssl > /dev/null

echo "[2/6] Generating a genuinely valid TLS cert (valid now, for 30 days)..."
sudo mkdir -p /etc/configapp/tls
sudo openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
    -keyout /etc/configapp/tls/key.pem \
    -out /etc/configapp/tls/cert.pem \
    -subj "/CN=localhost" 2>/dev/null

echo "[3/6] Recording the cert's real validity window for later comparison..."
sudo openssl x509 -in /etc/configapp/tls/cert.pem -noout -dates | sudo tee /var/tmp/lab21_cert_dates.txt > /dev/null

echo "[4/6] Starting a local HTTPS test endpoint on :8443 using that cert..."
sudo pkill -f "openssl s_server" 2>/dev/null || true
sleep 1
sudo nohup openssl s_server -accept 8443 -cert /etc/configapp/tls/cert.pem -key /etc/configapp/tls/key.pem -www \
    > /var/tmp/lab21_sserver.log 2>&1 &
disown
sleep 1

echo "[5/6] Stopping and masking chronyd, disabling NTP sync..."
sudo timedatectl set-ntp false
sudo systemctl stop chrony
sudo systemctl mask chrony

echo "[6/6] Jumping the system clock 60 days into the future..."
sudo date -s "+60 days" > /dev/null
date

echo
echo "Done. The clock is now 60 days ahead and nothing is correcting it."
echo "Confirm the (misleading) symptom:"
echo "  curl -v https://localhost:8443/ 2>&1 | grep -i -A2 'certificate'"
echo
echo "IMPORTANT: run reset.sh (or Step 6's fix) when you're done to restore"
echo "the clock - do not leave a VM's clock skewed 60 days into the future."
