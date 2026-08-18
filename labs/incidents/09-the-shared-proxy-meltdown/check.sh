#!/usr/bin/env bash
# Incident 09 check - mirrors how this was paged: "service-a is
# throwing connection errors." Sends a fresh burst of concurrent
# requests into service-b's hung endpoint (recreating real load, not
# just checking leftover state), then requires service-a to actually
# recover within a bounded window - not instantly during the burst
# (a correctly-configured timeout still takes a few seconds to release
# held connections), but well before service-b's underlying hang
# would ever resolve on its own.
set -uo pipefail

RECOVERY_TIMEOUT=15  # seconds to wait for service-a to recover

if ! systemctl is-active --quiet nginx 2>/dev/null; then
    echo "[FAIL] nginx is not running - run setup.sh first"
    exit 1
fi
if ! systemctl is-active --quiet service-a.service 2>/dev/null; then
    echo "[FAIL] service-a.service is not running - run setup.sh first"
    exit 1
fi

echo "[check] sending a fresh burst at service-b's hung endpoint..."
for i in 1 2 3 4 5 6; do
    curl -s -m 60 http://127.0.0.1:8080/b/ -o /dev/null &
    disown 2>/dev/null || true
done
sleep 1

echo "[check] polling service-a for recovery (up to ${RECOVERY_TIMEOUT}s)..."
START=$(date +%s)
while true; do
    CODE=$(curl -s -m 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/a/ 2>/dev/null || echo "000")
    NOW=$(date +%s)
    ELAPSED=$((NOW - START))
    echo "[check]   t+${ELAPSED}s: HTTP $CODE"
    if [ "$CODE" = "200" ]; then
        echo "[PASS] service-a recovered within ${ELAPSED}s - it's no longer sharing an unbounded blast radius with service-b."
        exit 0
    fi
    if [ "$ELAPSED" -ge "$RECOVERY_TIMEOUT" ]; then
        echo "[FAIL] service-a did not recover within ${RECOVERY_TIMEOUT}s - it's still being starved by service-b's hung requests."
        exit 1
    fi
    sleep 1
done
