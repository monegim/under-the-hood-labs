#!/usr/bin/env bash
# Incident 07 check - mirrors how this was paged: "signups are
# failing." Fires a handful of real /signup requests and requires
# every one of them to actually succeed.
set -uo pipefail

APP_URL="${APP_URL:-http://localhost:8080}"
N="${N:-5}"

if ! curl -s -o /dev/null -w '%{http_code}' "$APP_URL/health" 2>/dev/null | grep -q 200; then
    echo "[FAIL] app is not reachable at $APP_URL/health"
    exit 1
fi

FAILS=0
for i in $(seq 1 "$N"); do
    tmpfile=$(mktemp)
    code=$(curl -s -o "$tmpfile" -w '%{http_code}' --max-time 10 \
        -X POST "$APP_URL/signup" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"checker$i@example.com\"}" 2>/dev/null || echo "000")
    body=$(cat "$tmpfile" 2>/dev/null || echo "")
    rm -f "$tmpfile"

    echo "[check] signup #$i: HTTP $code - $body"
    if [ "$code" != "200" ]; then
        FAILS=$((FAILS+1))
    fi
done

if [ "$FAILS" -eq 0 ]; then
    echo "[PASS] all $N signups succeeded - incident resolved."
    exit 0
else
    echo "[FAIL] $FAILS/$N signups failed - incident not resolved."
    exit 1
fi
