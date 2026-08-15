#!/usr/bin/env bash
# Lab 22 reset — remove any iptables DROP rule left over from a previous
# attempt (for both possible answer IPs, base and Challenge B), then
# rebuild the log directory from scratch via setup.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] removing any iptables DROP rules from a previous attempt..."
sudo iptables -D INPUT -s 203.0.113.77 -j DROP 2>/dev/null || true
sudo iptables -D INPUT -s 203.0.113.200 -j DROP 2>/dev/null || true

echo "[reset] rebuilding logs via setup.sh..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
