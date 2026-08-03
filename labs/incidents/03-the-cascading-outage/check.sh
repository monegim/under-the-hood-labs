#!/usr/bin/env bash
# Incident 03 check - mirrors how this was paged: can a customer
# actually fetch/confirm an order? Fires a handful of real requests
# through orders-service (which itself depends on auth-service) and
# requires all of them to succeed.
set -uo pipefail

N="${N:-10}"
FAILS=0

echo "[check] confirming orders-service can serve real requests (which depend on auth-service)..."
for i in $(seq 1 "$N"); do
    tmpfile=$(mktemp)
    code=$(curl -s -o "$tmpfile" -w '%{http_code}' --max-time 5 "http://localhost:8001/orders/$i" 2>/dev/null || echo "000")
    body=$(cat "$tmpfile" 2>/dev/null || echo "")
    rm -f "$tmpfile"
    if [ "$code" != "200" ]; then
        echo "[check] request $i failed: HTTP $code - $body"
        FAILS=$((FAILS+1))
    fi
done

echo "[check] $((N-FAILS))/$N requests succeeded"

if [ "$FAILS" -eq 0 ]; then
    echo "[PASS] orders-service is serving requests normally - incident resolved."
    exit 0
else
    echo "[FAIL] incident not resolved - orders-service is still failing requests."
    echo "[check] hint: check auth-service directly too:"
    echo "  curl -s http://localhost:8000/health"
    echo "  curl -s -X POST http://localhost:8000/validate"
    exit 1
fi
