#!/usr/bin/env bash
# Incident 08 check - mirrors how this was paged: "checkout is slow."
# Fires a handful of real /checkout requests and requires each one to
# complete quickly.
set -uo pipefail

APP_URL="${APP_URL:-http://localhost:8090}"
N="${N:-5}"
LATENCY_THRESHOLD="1.0"  # seconds

if ! curl -s -o /dev/null -w '%{http_code}' "$APP_URL/health" 2>/dev/null | grep -q 200; then
    echo "[FAIL] frontend is not reachable at $APP_URL/health"
    exit 1
fi

FAILS=0
for i in $(seq 1 "$N"); do
    tmpfile=$(mktemp)
    time_total=$(curl -s -o "$tmpfile" -w '%{time_total}' --max-time 10 \
        -X POST "$APP_URL/checkout" 2>/dev/null || echo "10.0")
    body=$(cat "$tmpfile" 2>/dev/null || echo "")
    rm -f "$tmpfile"

    echo "[check] checkout #$i: ${time_total}s - $body"
    if awk -v t="$time_total" -v thr="$LATENCY_THRESHOLD" 'BEGIN{exit !(t>thr)}'; then
        FAILS=$((FAILS+1))
    fi
done

if [ "$FAILS" -eq 0 ]; then
    echo "[PASS] all /checkout calls completed under ${LATENCY_THRESHOLD}s - incident resolved."
    exit 0
else
    echo "[FAIL] $FAILS/$N /checkout calls exceeded ${LATENCY_THRESHOLD}s - incident not resolved."
    exit 1
fi
