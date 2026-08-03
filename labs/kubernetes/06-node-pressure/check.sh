#!/usr/bin/env bash
# Lab 6 — Node Under Memory Pressure — check.sh
#
# Verifies the node's MemoryPressure and DiskPressure Conditions are both
# False, and that a fresh BestEffort pod can be scheduled and reach
# Running (i.e. nothing is actively being evicted right now).
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 6 — Node Under Memory Pressure"
echo

CTX="kind-k8s06"
NODE="k8s06-control-plane"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

for cond in MemoryPressure DiskPressure PIDPressure; do
    STATUS=$(kubectl --context "${CTX}" get node "${NODE}" -o jsonpath="{.status.conditions[?(@.type==\"${cond}\")].status}" 2>/dev/null || true)
    if [ "$STATUS" = "False" ]; then
        ok "node condition ${cond} is False"
    else
        bad "node condition ${cond} is '${STATUS:-unknown}' (expected False)"
    fi
done

echo "[check] scheduling a test pod to confirm the node accepts new BestEffort workloads..."
kubectl --context "${CTX}" delete pod check-schedule-test --ignore-not-found >/dev/null 2>&1 || true
if kubectl --context "${CTX}" run check-schedule-test --image=nginx --restart=Never >/dev/null 2>&1 \
   && kubectl --context "${CTX}" wait --for=condition=Ready pod/check-schedule-test --timeout=60s >/dev/null 2>&1; then
    ok "test pod scheduled and became Ready"
    kubectl --context "${CTX}" delete pod check-schedule-test --ignore-not-found >/dev/null 2>&1 || true
else
    bad "test pod did not become Ready within 60s"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] node is healthy - no pressure conditions active."
    exit 0
else
    exit 1
fi
