#!/usr/bin/env bash
# Incident 06 check - mirrors how this was paged: the rollout "succeeded"
# but real checkout traffic was failing. This does NOT check
# `kubectl rollout status` (that already reports success throughout the
# entire incident - that's the trap) or the readiness probe. It checks
# the actual business-facing symptom: does POST /checkout work.
set -uo pipefail

CLUSTER="incident06"
CTX="kind-${CLUSTER}"
N="${N:-10}"

fail() { echo "[FAIL] $1"; exit 1; }

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    fail "cluster '${CTX}' is not reachable (did you run setup.sh?)"
fi

echo "[check] all checkout-api pods report Ready (expected - this alone never told the whole story)..."
kubectl --context "${CTX}" get pods -l app=checkout-api -o wide

echo "[check] port-forwarding to checkout-api..."
kubectl --context "${CTX}" port-forward svc/checkout-api 18080:80 >/tmp/incident06-check-pf.log 2>&1 &
PF_PID=$!
trap 'kill "$PF_PID" >/dev/null 2>&1 || true' EXIT
sleep 3

echo "[check] firing $N real /checkout requests..."
ok=0
fail_count=0
for i in $(seq 1 "$N"); do
    CODE=$(curl -s -o /tmp/incident06-check-body.json -w '%{http_code}' --max-time 5 \
        -X POST http://localhost:18080/checkout \
        -H "Content-Type: application/json" \
        -d "{\"item\":\"item-$i\"}")
    if [ "$CODE" = "200" ]; then
        ok=$((ok+1))
    else
        fail_count=$((fail_count+1))
        echo "      request $i -> HTTP $CODE: $(cat /tmp/incident06-check-body.json)"
    fi
done

echo
echo "[check] $ok/$N checkout requests succeeded"

if [ "$fail_count" -eq 0 ]; then
    echo "[PASS] checkout is actually working - incident resolved."
    exit 0
else
    echo "[FAIL] $fail_count/$N checkout requests failed - incident not resolved (rollout may look 'successful' anyway)."
    exit 1
fi
