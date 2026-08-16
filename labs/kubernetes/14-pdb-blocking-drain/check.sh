#!/usr/bin/env bash
# Lab 14 — PDB Blocking Drain — check.sh
#
# Verifies the checkout Deployment is healthy and that the PDB currently
# allows at least 1 disruption — i.e. there's enough headroom to safely
# drain a node right now, which is the "resolved" state this lab is
# teaching (create headroom, don't force through the budget).
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 14 — PDB Blocking Drain"
echo

CTX="kind-k8s14"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

AVAILABLE=$(kubectl --context "${CTX}" get deployment checkout -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)
if [ -n "$AVAILABLE" ] && [ "$AVAILABLE" -ge 1 ] 2>/dev/null; then
    ok "deployment/checkout has ${AVAILABLE} Available replica(s)"
else
    bad "deployment/checkout has no Available replicas"
fi

if kubectl --context "${CTX}" get pdb checkout-pdb >/dev/null 2>&1; then
    ok "pdb/checkout-pdb exists"
else
    bad "pdb/checkout-pdb does not exist"
fi

ALLOWED=$(kubectl --context "${CTX}" get pdb checkout-pdb -o jsonpath='{.status.disruptionsAllowed}' 2>/dev/null || true)
if [ -n "$ALLOWED" ] && [ "$ALLOWED" -ge 1 ] 2>/dev/null; then
    ok "pdb/checkout-pdb currently allows ${ALLOWED} disruption(s) — safe to drain"
else
    bad "pdb/checkout-pdb allows 0 disruptions (scale checkout up before draining)"
fi

NODE_STATUS=$(kubectl --context "${CTX}" get node k8s14-worker -o jsonpath='{.spec.unschedulable}' 2>/dev/null || true)
if [ "$NODE_STATUS" = "true" ]; then
    bad "node k8s14-worker is still cordoned (uncordon it if you're done with maintenance)"
else
    ok "node k8s14-worker is schedulable (not cordoned)"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] checkout is healthy and has enough PDB headroom to safely drain a node."
    exit 0
else
    exit 1
fi
