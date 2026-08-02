#!/usr/bin/env bash
# Lab 1 — Pod Networking Broken — check.sh
#
# Verifies frontend can currently reach backend-svc over HTTP. Exits 0 only
# if the request actually succeeds (curl exit code 0 AND an HTTP response),
# not just "pod is Running".
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 1 — Pod Networking Broken"
echo

CTX="kind-k8s01"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

for pod in frontend backend; do
    STATUS=$(kubectl --context "${CTX}" -n shop get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [ "$STATUS" = "Running" ]; then
        ok "pod/$pod is Running"
    else
        bad "pod/$pod is not Running (status: '${STATUS:-not found}')"
    fi
done

if kubectl --context "${CTX}" -n shop get svc backend-svc >/dev/null 2>&1; then
    ok "svc/backend-svc exists"
else
    bad "svc/backend-svc does not exist"
fi

ENDPOINTS=$(kubectl --context "${CTX}" -n shop get endpoints backend-svc -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
if [ -n "$ENDPOINTS" ]; then
    ok "svc/backend-svc has endpoint(s): $ENDPOINTS"
else
    bad "svc/backend-svc has no endpoints"
fi

echo "[check] attempting frontend -> backend-svc HTTP request (5s timeout)..."
if HTTP_CODE=$(kubectl --context "${CTX}" -n shop exec frontend -- curl -m 5 -sS -o /dev/null -w "%{http_code}" http://backend-svc 2>/dev/null) && [ "$HTTP_CODE" = "200" ]; then
    ok "frontend can reach backend-svc (HTTP $HTTP_CODE)"
else
    bad "frontend cannot reach backend-svc (NetworkPolicy still blocking, or endpoint/service issue)"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] frontend -> backend-svc connectivity is healthy."
    exit 0
else
    exit 1
fi
