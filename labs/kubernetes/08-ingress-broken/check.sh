#!/usr/bin/env bash
# Lab 8 — Ingress Broken — check.sh
#
# Verifies the Ingress actually routes to the backend correctly: real
# HTTP 200 via curl with the right Host header. Exits 0 only if the
# request truly succeeds end-to-end through ingress-nginx.
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 8 — Ingress Broken"
echo

CTX="kind-k8s08"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

READY=$(kubectl --context "${CTX}" -n ingress-nginx get pods -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
if [ "$READY" = "True" ]; then
    ok "ingress-nginx controller is Ready"
else
    bad "ingress-nginx controller is not Ready"
fi

INGRESS_CLASS=$(kubectl --context "${CTX}" get ingress web-ingress -o jsonpath='{.spec.ingressClassName}' 2>/dev/null || true)
if kubectl --context "${CTX}" get ingressclass "$INGRESS_CLASS" >/dev/null 2>&1; then
    ok "web-ingress references a real IngressClass ('$INGRESS_CLASS')"
else
    bad "web-ingress's ingressClassName ('$INGRESS_CLASS') does not match any IngressClass"
fi

echo "[check] attempting a real HTTP request through the Ingress..."
HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" -m 8 -H "Host: lab8.local" http://localhost/ 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    ok "HTTP request through Ingress succeeded (200)"
else
    bad "HTTP request through Ingress failed (got HTTP $HTTP_CODE)"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] Ingress routing is healthy."
    exit 0
else
    exit 1
fi
