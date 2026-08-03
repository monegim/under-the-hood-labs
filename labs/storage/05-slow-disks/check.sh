#!/usr/bin/env bash
# Lab 5 check — general health check: is the victim service's recent
# write latency back to a healthy baseline, and is there a runaway I/O
# hog still active?
set -uo pipefail

PASS=0
LOG_DIR=/var/log/slowlab
STATE_DIR=/var/lib/slowlab
THRESHOLD_MS=50

if [ ! -f "$LOG_DIR/service.log" ]; then
    echo "[FAIL] no service.log found - has setup.sh been run?"
    exit 1
fi

if ! sudo test -f "$STATE_DIR/victim.pid" || ! sudo kill -0 "$(sudo cat "$STATE_DIR/victim.pid")" 2>/dev/null; then
    echo "[FAIL] victim service is not running."
    PASS=1
fi

echo "[check] recent write latency samples:"
tail -5 "$LOG_DIR/service.log"

RECENT_MAX=$(tail -10 "$LOG_DIR/service.log" | grep -oE 'write_latency_ms=[0-9]+' | cut -d= -f2 | sort -n | tail -1)
if [ -z "$RECENT_MAX" ]; then
    echo "[FAIL] could not parse recent latency samples."
    exit 1
fi
echo "[check] max of last 10 samples: ${RECENT_MAX}ms (threshold: ${THRESHOLD_MS}ms)"
if [ "$RECENT_MAX" -gt "$THRESHOLD_MS" ]; then
    echo "[FAIL] write latency is above the healthy threshold."
    PASS=1
fi

echo "[check] checking for a runaway I/O hog (fio) still active..."
if pgrep -f 'fio --name=hog' >/dev/null 2>&1; then
    HOGPID=$(pgrep -f 'fio --name=hog' | head -1)
    IOCLASS=$(ionice -p "$HOGPID" 2>/dev/null || true)
    echo "[check] fio hog still running (pid $HOGPID), ionice: $IOCLASS"
    echo "$IOCLASS" | grep -qi "idle" || echo "[check] note: hog is not deprioritized to idle class."
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] victim service latency is healthy."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
