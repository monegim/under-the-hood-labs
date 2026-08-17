#!/usr/bin/env bash
# Lab 20 — Scheduler Cannot Place Pod — check.sh
#
# Verifies the webapp Deployment has a Running, Ready Pod actually
# scheduled onto the node — the FailedScheduling incident is resolved,
# not just retried into the same Pending state.
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 20 — Scheduler Cannot Place Pod"
echo

CTX="kind-k8s20"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

AVAILABLE=$(kubectl --context "${CTX}" get deployment webapp -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)
if [ -n "$AVAILABLE" ] && [ "$AVAILABLE" -ge 1 ] 2>/dev/null; then
    ok "deployment/webapp has ${AVAILABLE} Available replica(s)"
else
    bad "deployment/webapp has no Available replicas"
fi

PENDING_WEBAPP=$(kubectl --context "${CTX}" get pods -l app=webapp --field-selector=status.phase=Pending -o name 2>/dev/null || true)
if [ -n "$PENDING_WEBAPP" ]; then
    bad "a webapp Pod is still Pending: ${PENDING_WEBAPP}"
else
    ok "no webapp Pod is stuck Pending"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] webapp is Running, actually scheduled onto the node."
    exit 0
else
    exit 1
fi
