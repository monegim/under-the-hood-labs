#!/usr/bin/env bash
# Lab 5 — PVC Stuck — check.sh
#
# Verifies data-pvc (and baseline-pvc) are both Bound. Exits 0 only if
# both PVCs report phase Bound.
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 5 — PVC Stuck"
echo

CTX="kind-k8s05"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

for pvc in baseline-pvc data-pvc; do
    PHASE=$(kubectl --context "${CTX}" get pvc "$pvc" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [ "$PHASE" = "Bound" ]; then
        ok "pvc/$pvc is Bound"
    else
        bad "pvc/$pvc is not Bound (phase: '${PHASE:-not found}')"
    fi
done

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] all PVCs are Bound."
    exit 0
else
    exit 1
fi
