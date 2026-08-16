#!/usr/bin/env bash
# Lab 14 check — verifies swap is no longer full (healthy headroom) and
# the memory hog is no longer running/growing.
set -uo pipefail

PASS=0
STATE_DIR=/var/lib/swaplab14
SWAPFILE="$STATE_DIR/swapfile"

echo "[check] is the hog process still running?"
if [ -f "$STATE_DIR/hog.pid" ] && sudo kill -0 "$(cat "$STATE_DIR/hog.pid")" 2>/dev/null; then
    echo "[FAIL] the original hog process is still running (pid $(cat "$STATE_DIR/hog.pid"))."
    PASS=1
else
    echo "[check] original hog process is gone."
fi

echo "[check] current swap usage across ALL active swap (this lab's swapfile + any others)..."
swapon --show --bytes 2>/dev/null | tail -n +2 | while read -r NAME TYPE SIZE USED PRIO; do
    echo "  $NAME: used=$USED / size=$SIZE"
done

TOTAL_SWAP=$(awk '/SwapTotal/ {print $2}' /proc/meminfo)
FREE_SWAP=$(awk '/SwapFree/ {print $2}' /proc/meminfo)
if [ -z "$TOTAL_SWAP" ] || [ "$TOTAL_SWAP" -eq 0 ]; then
    echo "[FAIL] no swap is active at all — did something swapoff everything, including pre-existing swap?"
    PASS=1
else
    USED_PCT=$(( (TOTAL_SWAP - FREE_SWAP) * 100 / TOTAL_SWAP ))
    echo "[check] overall swap usage: ${USED_PCT}%"
    if [ "$USED_PCT" -gt 80 ]; then
        echo "[FAIL] swap is still over 80% used — not a healthy state."
        PASS=1
    fi
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] hog is gone, swap usage is back to a healthy level."
    exit 0
else
    echo "[FAIL] see details above."
    exit 1
fi
