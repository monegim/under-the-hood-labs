#!/usr/bin/env bash
# Lab 15 reset — kill any lingering stress-ng/capture processes, then
# re-run setup.sh (self-contained: writes fresh capture files and reference
# samples, safe to re-run as-is).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] killing any lingering stress-ng process..."
pkill -x stress-ng 2>/dev/null || true

echo "[reset] killing any lingering vmstat/mpstat capture processes from the lab..."
pkill -f "vmstat 1 20" 2>/dev/null || true
pkill -f "mpstat -P ALL 1 20" 2>/dev/null || true

echo "[reset] re-running setup.sh to rebuild the lab's capture/reference files..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
