#!/usr/bin/env bash
# Lab 10 reset — undo any fix, clean up leftover hog units, then re-run setup.sh
# to recreate the OOM-priming conditions (900M buffer pool in a 1200M slice).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] stopping mysql.service..."
sudo systemctl stop mysql 2>/dev/null || true

echo "[reset] stopping any leftover stress-ng hog units from the lab/challenges..."
sudo systemctl stop oom-lab-hog oom-lab-hog2 oom-lab-hog3 2>/dev/null || true
sudo pkill -f 'stress-ng --vm' 2>/dev/null || true

echo "[reset] clearing failed-unit records so transient hog units can be reused..."
sudo systemctl reset-failed 2>/dev/null || true

echo "[reset] re-running setup.sh to recreate the incident (900M buffer pool, 1200M slice)..."
sudo bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
