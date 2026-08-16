#!/usr/bin/env bash
# Lab 13 — StatefulSet PVC Mismatch — check.sh
#
# Verifies the StatefulSet is back at 3/3 Ready replicas with 3 Bound
# PVCs. This lab's "break" is a conceptual trap (surprising PVC reuse),
# not a persistent broken state, so "healthy" here means the StatefulSet
# is fully reconciled, whichever path (reused or fresh PVCs) you took to
# get there.
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 13 — StatefulSet PVC Mismatch"
echo

CTX="kind-k8s13"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

READY=$(kubectl --context "${CTX}" get statefulset myapp -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
if [ "${READY:-0}" = "3" ]; then
    ok "statefulset/myapp has 3/3 Ready replicas"
else
    bad "statefulset/myapp has ${READY:-0}/3 Ready replicas"
fi

for pvc in data-myapp-0 data-myapp-1 data-myapp-2; do
    PHASE=$(kubectl --context "${CTX}" get pvc "$pvc" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [ "$PHASE" = "Bound" ]; then
        ok "pvc/$pvc is Bound"
    else
        bad "pvc/$pvc is not Bound (status: '${PHASE:-not found}')"
    fi
done

echo "[check] confirming each Pod can actually read its volume..."
ALL_READABLE=1
for i in 0 1 2; do
    if ! kubectl --context "${CTX}" exec "myapp-${i}" -- cat /data/created-at >/dev/null 2>&1; then
        ALL_READABLE=0
        bad "myapp-${i} cannot read /data/created-at from its volume"
    fi
done
if [ "$ALL_READABLE" -eq 1 ]; then
    ok "all 3 Pods can read their volume's /data/created-at"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] StatefulSet myapp is fully reconciled at 3/3 with all volumes mounted."
    exit 0
else
    exit 1
fi
