#!/usr/bin/env bash
# Incident 05 reset - since a D-state process can't simply be killed,
# this FIRST removes the iptables block (letting anything stuck finally
# unblock and exit), waits, then tears everything down cleanly and
# re-runs setup.sh to reproduce the incident fresh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] removing any NFS-port iptables blocks (letting stuck processes unblock)..."
sudo iptables -D OUTPUT -p tcp --dport 2049 -j DROP 2>/dev/null || true
sudo iptables -D INPUT -p tcp --sport 2049 -j DROP 2>/dev/null || true

echo "[reset] giving any previously-stuck process a moment to actually exit..."
sleep 5

echo "[reset] stopping upload-worker.service..."
sudo systemctl stop upload-worker.service 2>/dev/null || true

echo "[reset] unmounting /mnt/uploads..."
sudo umount /mnt/uploads 2>/dev/null || sudo umount -f /mnt/uploads 2>/dev/null || true

echo "[reset] removing lab state..."
sudo rm -rf /var/lib/uploadlab
sudo rm -f /srv/uploads/* 2>/dev/null || true

echo "[reset] re-running setup.sh to recreate the incident..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
