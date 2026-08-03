#!/usr/bin/env bash
# Lab 9 — API Server Unavailable — check.sh
#
# Verifies kubectl can actually reach the cluster and list nodes, and
# that the control-plane node container is Up. Exits 0 only if both
# hold - this check intentionally does NOT rely only on the node
# container being up, since the whole point of this lab is that the API
# server can be down while the node itself is fine.
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 9 — API Server Unavailable"
echo

CTX="kind-k8s09"
NODE="k8s09-control-plane"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if docker ps --filter "name=${NODE}" --filter "status=running" --format '{{.Names}}' 2>/dev/null | grep -qx "${NODE}"; then
    ok "node container '${NODE}' is Up"
else
    bad "node container '${NODE}' is not running (did you run 'docker start ${NODE}' after Challenge B?)"
fi

echo "[check] attempting kubectl get nodes (10s timeout)..."
if kubectl --context "${CTX}" --request-timeout=10s get nodes >/dev/null 2>&1; then
    ok "kubectl can reach the API server"
else
    bad "kubectl cannot reach the API server"
fi

NODE_STATUS=$(kubectl --context "${CTX}" --request-timeout=10s get node "${NODE}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
if [ "$NODE_STATUS" = "True" ]; then
    ok "node '${NODE}' reports Ready"
else
    bad "node '${NODE}' does not report Ready (got '${NODE_STATUS:-unreachable}')"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] API server is healthy and reachable."
    exit 0
else
    exit 1
fi
