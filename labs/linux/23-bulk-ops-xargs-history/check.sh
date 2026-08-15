#!/usr/bin/env bash
# Lab 23 check — verifies the cache is genuinely empty (including the
# root-owned quarantine subdirectory and anything added by either
# challenge), the runaway workers are gone, and the unrelated
# "network-worker-monitor" process is still alive (i.e. it wasn't
# collateral damage from an overly loose pkill/xargs-kill pattern).
set -uo pipefail

PASS=0
CACHE=/var/tmp/lab23-cache
WORKERS=/var/tmp/lab23-workers
IMPORTANT=/var/tmp/lab23-important

echo "[check] any *.tmp files left anywhere under $CACHE (including quarantine)?"
LEFTOVER=$(sudo find "$CACHE" -name '*.tmp' 2>/dev/null | wc -l | tr -d ' ')
echo "[check] leftover *.tmp count: $LEFTOVER"
if [ "$LEFTOVER" -ne 0 ]; then
    echo "[FAIL] $LEFTOVER stale files remain."
    sudo find "$CACHE" -name '*.tmp' 2>/dev/null | head -5
    PASS=1
fi

echo "[check] any runaway worker processes still running?"
WORKER_COUNT=$(pgrep -fc "$WORKERS/worker-" 2>/dev/null || echo 0)
echo "[check] worker process count: $WORKER_COUNT"
if [ "$WORKER_COUNT" -ne 0 ]; then
    echo "[FAIL] $WORKER_COUNT worker process(es) still running."
    PASS=1
fi

echo "[check] is the unrelated network-worker-monitor process still alive?"
if pgrep -f "$IMPORTANT/network-worker-monitor.sh" >/dev/null 2>&1; then
    echo "[check] network-worker-monitor is running, as it should be."
else
    echo "[FAIL] network-worker-monitor is NOT running — it looks like it was killed by mistake."
    PASS=1
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] cache is clean, workers are gone, the unrelated service is untouched."
    exit 0
else
    echo "[FAIL] see details above."
    exit 1
fi
