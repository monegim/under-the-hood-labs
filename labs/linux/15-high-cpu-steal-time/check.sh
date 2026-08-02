#!/usr/bin/env bash
# Lab 15 check — is the CPU load generator from setup.sh no longer running?
set -uo pipefail

PASS=0

echo "[check] checking for a running stress-ng process from this lab..."
if pgrep -x stress-ng >/dev/null 2>&1; then
    echo "[FAIL] stress-ng is still running:"
    pgrep -af stress-ng
    PASS=1
else
    echo "[check] no stress-ng process running."
fi

echo "[check] checking no leftover vmstat/mpstat capture processes are still running..."
if pgrep -f "vmstat 1 20" >/dev/null 2>&1 || pgrep -f "mpstat -P ALL 1 20" >/dev/null 2>&1; then
    echo "[FAIL] a leftover vmstat/mpstat capture process from the lab is still running:"
    pgrep -af "vmstat 1 20" 2>/dev/null
    pgrep -af "mpstat -P ALL 1 20" 2>/dev/null
    PASS=1
else
    echo "[check] no leftover vmstat/mpstat capture processes."
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] no lab CPU load generator or capture process is currently running."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
