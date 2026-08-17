#!/usr/bin/env bash
set -uo pipefail

# Lab 31 check - fires enough requests through the load balancer to
# cycle through every backend at least twice, and requires every
# single one to succeed.

LB_URL="${LB_URL:-http://localhost:8091}"
N=9

if ! curl -s -o /dev/null http://localhost:8091/api/data 2>/dev/null; then
    echo "[FAIL] haproxy is not reachable at $LB_URL - run setup.sh first"
    exit 1
fi

FAILS=0
for i in $(seq 1 "$N"); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$LB_URL/api/data" 2>/dev/null || echo "000")
    echo "[check] request #$i: HTTP $code"
    [ "$code" != "200" ] && FAILS=$((FAILS+1))
done

if [ "$FAILS" -eq 0 ]; then
    echo "[PASS] all $N requests succeeded - every backend actually in rotation is healthy."
    exit 0
else
    echo "[FAIL] $FAILS/$N requests failed - a backend that's failing real traffic is still in rotation."
    exit 1
fi
