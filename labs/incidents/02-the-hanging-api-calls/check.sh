#!/usr/bin/env bash
# Incident 02 check - mirrors how this was paged: report generation for
# specific (large) customers timing out. Confirms both a small report
# (sanity check that the environment works at all) and the large
# acme-corp report succeed quickly.
set -uo pipefail

LAB="mtu-incident"
API="clab-${LAB}-api"
R1="clab-${LAB}-r1"
R2="clab-${LAB}-r2"
DB="clab-${LAB}-db"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying containers are running..."
for c in "$API" "$R1" "$R2" "$DB"; do
    status=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
    [ "$status" = "true" ] || fail "container $c is not running (deploy the topology first)"
done

echo "[check] small report (customer_id=1) - sanity check..."
SMALL=$(docker exec "$API" curl -s --max-time 8 "http://localhost:8000/report?customer_id=1")
echo "$SMALL"
echo "$SMALL" | grep -q '"ok": true' || fail "even the small report failed - environment isn't healthy"

echo "[check] large report (customer_id=999, acme-corp) - the actual paged symptom..."
START=$(date +%s)
BIG=$(docker exec "$API" curl -s --max-time 15 "http://localhost:8000/report?customer_id=999")
END=$(date +%s)
ELAPSED=$((END - START))
echo "$BIG"
echo "[check] wall-clock time: ${ELAPSED}s"

echo "$BIG" | grep -q '"ok": true' || fail "large report failed or timed out - incident not resolved"
[ "$ELAPSED" -le 5 ] || fail "large report eventually succeeded but took ${ELAPSED}s (>5s) - still degraded"

echo "[PASS] large report requests succeed quickly - incident resolved"
exit 0
