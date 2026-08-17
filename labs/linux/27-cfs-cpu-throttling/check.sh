#!/usr/bin/env bash
# Lab 27 check — runs the same fixed CPU burst and verifies it completes
# quickly (under 200ms) without meaningfully increasing the cgroup's
# throttled time, proving the quota now has enough headroom for it.
set -uo pipefail

APP="lab27-app"
MAX_MS=200

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying $APP is running..."
status=$(docker inspect -f '{{.State.Running}}' "$APP" 2>/dev/null)
[ "$status" = "true" ] || fail "container $APP is not running (run setup.sh first)"

echo "[check] current CPU quota:"
docker exec "$APP" cat /sys/fs/cgroup/cpu.max

BEFORE=$(docker exec "$APP" grep throttled_usec /sys/fs/cgroup/cpu.stat | awk '{print $2}')

START=$(date +%s%N)
docker exec "$APP" stress-ng --cpu 2 --cpu-method fibonacci --cpu-ops 4000000 --metrics-brief >/dev/null 2>&1
END=$(date +%s%N)
ELAPSED_MS=$(( (END - START) / 1000000 ))

AFTER=$(docker exec "$APP" grep throttled_usec /sys/fs/cgroup/cpu.stat | awk '{print $2}')
DELTA=$((AFTER - BEFORE))

echo "[check] fixed workload took ${ELAPSED_MS}ms (threshold: ${MAX_MS}ms)"
echo "[check] throttled_usec increased by ${DELTA}us during this run"

[ "$ELAPSED_MS" -lt "$MAX_MS" ] || fail "workload took ${ELAPSED_MS}ms — still being throttled"

echo "[PASS] the workload completes quickly with negligible additional throttling."
exit 0
