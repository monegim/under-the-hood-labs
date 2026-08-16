#!/usr/bin/env bash
# Lab 17 — Taints/Tolerations Mismatch — check.sh
#
# Verifies the 'web' deployment is fully Ready (either because it now
# tolerates the node's taint, or because the taint itself was removed).
# Exits 0 only if both replicas are actually Running.
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 17 — Taints/Tolerations Mismatch"
echo

CTX="kind-k8s17"
NODE="k8s17-control-plane"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

if ! kubectl --context "${CTX}" get deployment web >/dev/null 2>&1; then
    bad "web deployment not found"
    echo
    echo "[check] $PASS passed, $FAIL failed"
    exit 1
fi

DESIRED=$(kubectl --context "${CTX}" get deployment web -o jsonpath='{.spec.replicas}')
READY=$(kubectl --context "${CTX}" get deployment web -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [ "${READY:-0}" = "$DESIRED" ]; then
    ok "web deployment fully Ready ($READY/$DESIRED)"
else
    bad "web deployment not fully Ready (ready: ${READY:-0}, desired: $DESIRED)"
fi

PENDING=$(kubectl --context "${CTX}" get pods -l app=web --no-headers 2>/dev/null | grep -c Pending || true)
if [ "${PENDING:-0}" -eq 0 ]; then
    ok "no web pods stuck Pending"
else
    bad "${PENDING} web pod(s) still Pending"
fi

echo "[check] current node taints:"
kubectl --context "${CTX}" describe node "${NODE}" 2>/dev/null | grep "Taints:" || echo "      (could not read node taints)"

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] web is fully scheduled and Running."
    exit 0
else
    exit 1
fi
