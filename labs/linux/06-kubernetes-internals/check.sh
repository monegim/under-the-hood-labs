#!/usr/bin/env bash
# Lab 6 — Kubernetes Internals — check.sh
#
# Verifies the state README.md Steps 1-4 build:
#   - the "lab6" kind cluster exists and is reachable
#   - the nginx pod is Running/Ready
#   - the nginx-svc Service has at least one endpoint (i.e. it's actually
#     backed by the Ready pod, not just present as an object)
#
# All kubectl calls are scoped to the "kind-lab6" context specifically, so
# this never touches any other cluster/context you may have configured.
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad()  { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 6 — Kubernetes Internals"
echo

CTX="kind-lab6"

if ! command -v kind >/dev/null || ! command -v kubectl >/dev/null; then
    bad "kind and/or kubectl not found in PATH"
    echo
    echo "[check] $PASS passed, $FAIL failed"
    exit 1
fi

# --- cluster exists ---
if kind get clusters 2>/dev/null | grep -qx "lab6"; then
    ok "kind cluster 'lab6' exists"
else
    bad "kind cluster 'lab6' does not exist (did you run Step 1?)"
    echo
    echo "[check] $PASS passed, $FAIL failed"
    exit 1
fi

# --- cluster reachable ---
if kubectl --context "$CTX" cluster-info >/dev/null 2>&1; then
    ok "cluster is reachable (kubectl cluster-info)"
else
    bad "kubectl cluster-info failed against context $CTX — cluster may be unhealthy"
    echo
    echo "[check] $PASS passed, $FAIL failed"
    exit 1
fi

# --- nginx pod exists and is Running/Ready ---
POD_STATUS=$(kubectl --context "$CTX" get pod nginx -o jsonpath='{.status.phase}' 2>/dev/null || true)
if [ "$POD_STATUS" = "Running" ]; then
    ok "pod/nginx is Running"
else
    bad "pod/nginx is not Running (status: '${POD_STATUS:-not found}') — did you run Step 2?"
fi

POD_READY=$(kubectl --context "$CTX" get pod nginx -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
if [ "$POD_READY" = "True" ]; then
    ok "pod/nginx is Ready"
else
    bad "pod/nginx Ready condition is not True (got '${POD_READY:-none}')"
fi

# --- nginx-svc exists and has endpoints ---
if kubectl --context "$CTX" get svc nginx-svc >/dev/null 2>&1; then
    ok "svc/nginx-svc exists"
    ENDPOINTS=$(kubectl --context "$CTX" get endpoints nginx-svc -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
    if [ -n "$ENDPOINTS" ]; then
        ok "svc/nginx-svc has endpoint(s): $ENDPOINTS"
    else
        bad "svc/nginx-svc has no endpoints — it exists but isn't backed by any Ready pod (see Challenge A)"
    fi
else
    bad "svc/nginx-svc does not exist (did you run 'kubectl expose pod nginx --port=80 --name=nginx-svc'?)"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] kind cluster + nginx pod/service are healthy."
    exit 0
else
    exit 1
fi
