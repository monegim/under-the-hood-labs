#!/usr/bin/env bash
# Lab 23 reset — kill any leftover worker/important processes from a
# previous attempt, wipe the cache directory (including the root-owned
# quarantine subtree, which needs sudo to remove), then rebuild
# everything fresh via setup.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] killing any leftover worker/important processes..."
pkill -f "/var/tmp/lab23-workers/worker-" 2>/dev/null || true
pkill -f "/var/tmp/lab23-important/network-worker-monitor.sh" 2>/dev/null || true

echo "[reset] wiping the cache directory (sudo needed for quarantine/)..."
sudo rm -rf /var/tmp/lab23-cache /var/tmp/lab23-workers /var/tmp/lab23-important /var/tmp/lab23-cleanup-log

echo "[reset] rebuilding via setup.sh..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
