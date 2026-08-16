#!/usr/bin/env bash
# Lab 15 check — verifies the scheduler was actually changed away from
# 'none' AND that the sensitive writer's recent latency is healthy.
# Doesn't require one specific scheduler name (bfq/mq-deadline are both
# reasonable answers) — checks the observable outcome.
set -uo pipefail

PASS=0
STATE_DIR=/var/lib/ioschedlab15
LOG_DIR=/var/log/ioschedlab15
THRESHOLD_MS=200

if [ ! -f "$STATE_DIR/loopdev" ]; then
    echo "[FAIL] lab state missing — run setup.sh first."
    exit 1
fi
LOOPDEV=$(cat "$STATE_DIR/loopdev")
DEVNAME=$(basename "$LOOPDEV")
SCHED_FILE="/sys/block/$DEVNAME/queue/scheduler"

echo "[check] current scheduler for $LOOPDEV:"
if [ -f "$SCHED_FILE" ]; then
    cat "$SCHED_FILE"
    CURRENT=$(grep -oP '\[\K[^]]+' "$SCHED_FILE" 2>/dev/null || echo "")
    echo "[check] active: $CURRENT"
    if [ "$CURRENT" = "none" ]; then
        echo "[FAIL] scheduler is still 'none' — no fairness/latency shaping is active."
        PASS=1
    fi
else
    echo "[FAIL] $SCHED_FILE not found."
    PASS=1
fi

echo "[check] is the sensitive-writer process still running?"
if ! sudo test -f "$STATE_DIR/sensitive.pid" || ! sudo kill -0 "$(sudo cat "$STATE_DIR/sensitive.pid")" 2>/dev/null; then
    echo "[FAIL] sensitive writer process is not running."
    PASS=1
fi

if [ -f "$LOG_DIR/sensitive.log" ]; then
    echo "[check] recent write latency samples:"
    tail -5 "$LOG_DIR/sensitive.log"
    RECENT_MAX=$(tail -10 "$LOG_DIR/sensitive.log" | grep -oE 'write_latency_ms=[0-9]+' | cut -d= -f2 | sort -n | tail -1)
    if [ -n "$RECENT_MAX" ]; then
        echo "[check] max of last 10 samples: ${RECENT_MAX}ms (threshold: ${THRESHOLD_MS}ms)"
        if [ "$RECENT_MAX" -gt "$THRESHOLD_MS" ]; then
            echo "[FAIL] sensitive writer's latency is still above the healthy threshold."
            PASS=1
        fi
    else
        echo "[FAIL] could not parse recent latency samples."
        PASS=1
    fi
else
    echo "[FAIL] no sensitive.log found."
    PASS=1
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] scheduler changed away from 'none', sensitive writer latency is healthy."
    exit 0
else
    echo "[FAIL] see details above."
    exit 1
fi
