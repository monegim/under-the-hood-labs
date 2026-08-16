#!/usr/bin/env bash
# Incident 16 check - verifies both halves of the page are actually
# fixed: (1) orders-api /work is genuinely fast again, not just
# "reported as fast", and (2) the metrics agent is producing fresh
# samples again, not just serving a frozen JSON blob that happens to
# look healthy. Fixing only one of these is not a resolved incident.
set -uo pipefail

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] orders-api /work - real latency..."
REAL_MS=$(curl -s -o /dev/null -w '%{time_total}' --max-time 10 http://localhost:8080/work 2>/dev/null)
[ -n "$REAL_MS" ] || fail "orders-api /work did not respond at all"
REAL_MS_INT=$(awk "BEGIN{printf \"%d\", ${REAL_MS}*1000}")
echo "      /work wall-clock time: ${REAL_MS_INT}ms"
[ "$REAL_MS_INT" -le 500 ] || fail "orders-api /work is still slow (${REAL_MS_INT}ms > 500ms) - CPU pressure not resolved"

echo "[check] metrics-agent /metrics - freshness..."
METRICS=$(curl -s --max-time 5 http://localhost:9100/metrics 2>/dev/null)
[ -n "$METRICS" ] || fail "metrics-agent /metrics did not respond at all"
echo "      $METRICS"
TS=$(echo "$METRICS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["timestamp"])' 2>/dev/null)
[ -n "$TS" ] || fail "could not parse a timestamp out of /metrics"
NOW=$(date +%s)
AGE=$((NOW - TS))
echo "      sample age: ${AGE}s"
[ "$AGE" -le 10 ] || fail "metrics-agent's last sample is ${AGE}s old - it's still stuck, dashboard is still lying"

echo "[check] confirming the stale sample wasn't just coincidentally low-latency..."
REPORTED_MS=$(echo "$METRICS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["work_latency_ms"])' 2>/dev/null)
echo "      agent-reported work_latency_ms: ${REPORTED_MS}"

echo "[PASS] orders-api is fast for real, and the dashboard is telling the truth about it"
exit 0
