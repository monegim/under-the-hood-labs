#!/usr/bin/env bash
# Incident 01 check - mirrors how this incident was paged: login latency
# and error rate. Fires a burst of concurrent /login requests (valid
# credentials) and checks p99 latency and error rate against thresholds
# well below the incident's reported 1.2s / 12%.
set -uo pipefail

APP_URL="${APP_URL:-http://localhost:8080}"
N="${N:-20}"
P99_THRESHOLD="0.5"   # seconds - incident reported ~1.2s
ERROR_THRESHOLD="5"   # percent - incident reported 12%

if ! curl -s -o /dev/null -w '%{http_code}' "$APP_URL/health" 2>/dev/null | grep -q 200; then
    echo "[FAIL] app is not reachable at $APP_URL/health"
    exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

echo "[check] firing $N concurrent /login requests..."
for i in $(seq 1 "$N"); do
    (
        curl -s -o /dev/null --max-time 5 \
            -w "%{http_code} %{time_total}\n" \
            -X POST "$APP_URL/login" \
            -H "Content-Type: application/json" \
            -d '{"username":"demo","password":"demopass"}' \
            > "$tmpdir/$i.out" 2>/dev/null
        if [ ! -s "$tmpdir/$i.out" ]; then
            echo "000 5.000" > "$tmpdir/$i.out"
        fi
    ) &
done
wait

cat "$tmpdir"/*.out > "$tmpdir/all.out"
echo "[check] raw results:"
cat "$tmpdir/all.out"

errors=$(awk '$1 != "200" {c++} END {print c+0}' "$tmpdir/all.out")
error_rate=$(awk -v e="$errors" -v n="$N" 'BEGIN { printf "%.1f", (e/n)*100 }')
p99=$(awk '{print $2}' "$tmpdir/all.out" | sort -n | tail -1)

echo
echo "[check] error rate: ${error_rate}% (threshold: <= ${ERROR_THRESHOLD}%)"
echo "[check] worst-case latency: ${p99}s (threshold: <= ${P99_THRESHOLD}s)"

PASS=0
if awk -v e="$error_rate" -v t="$ERROR_THRESHOLD" 'BEGIN{exit !(e<=t)}'; then
    :
else
    PASS=1
fi
if awk -v p="$p99" -v t="$P99_THRESHOLD" 'BEGIN{exit !(p<=t)}'; then
    :
else
    PASS=1
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] logins are fast and reliable - incident resolved."
    exit 0
else
    echo "[FAIL] incident not resolved - latency and/or error rate still elevated."
    exit 1
fi
