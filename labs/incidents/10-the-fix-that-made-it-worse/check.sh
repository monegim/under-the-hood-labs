#!/usr/bin/env bash
# Incident 10 check - mirrors how this was paged: is the checkout
# error rate actually back to normal? Waits for client-traffic's own
# next periodic report (it logs a cumulative summary every 10s) and
# requires the failure rate in it to be at or below the level this
# service has always tolerated during its normal recurring traffic
# bursts.
set -uo pipefail

THRESHOLD=60  # max acceptable fail rate, percent - this service's
              # capacity is sized for average, not peak, load, so a
              # stable ~40% failure rate during bursts is expected and
              # normal; anything trending toward 100% is not

if ! systemctl is-active --quiet backend.service 2>/dev/null; then
    echo "[FAIL] backend.service is not running - run setup.sh first"
    exit 1
fi
if ! systemctl is-active --quiet client-traffic.service 2>/dev/null; then
    echo "[FAIL] client-traffic.service is not running - run setup.sh first"
    exit 1
fi

echo "[check] waiting for a fresh traffic report (up to 15s)..."
LINE=""
for i in $(seq 1 15); do
    LINE=$(sudo journalctl -u client-traffic --since "15 seconds ago" --no-pager 2>/dev/null | grep "checkout attempts" | tail -1)
    if [ -n "$LINE" ]; then
        break
    fi
    sleep 1
done

if [ -z "$LINE" ]; then
    echo "[FAIL] no traffic report seen - client-traffic.service may not be logging"
    exit 1
fi

echo "[check] $LINE"

RATE=$(echo "$LINE" | grep -oE '\([0-9]+%\)' | head -1 | tr -d '(%)')

if [ -z "$RATE" ]; then
    echo "[FAIL] could not parse failure rate from report line"
    exit 1
fi

if [ "$RATE" -le "$THRESHOLD" ]; then
    echo "[PASS] checkout failure rate is ${RATE}%, at or below the ${THRESHOLD}% this service normally tolerates during traffic bursts."
    exit 0
else
    echo "[FAIL] checkout failure rate is ${RATE}%, well above the ${THRESHOLD}% baseline - still degraded."
    exit 1
fi
