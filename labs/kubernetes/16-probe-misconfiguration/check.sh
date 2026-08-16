#!/usr/bin/env bash
# Lab 16 — Probe Misconfiguration — check.sh
#
# Verifies slow-app is fully Ready and, more importantly, watches its
# restart count for 30s to confirm it's actually stable now - a
# still-too-aggressive probe can look "Ready" for a moment and then kill
# the container again a few seconds later, so a point-in-time check alone
# isn't enough here.
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 16 — Probe Misconfiguration"
echo

CTX="kind-k8s16"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

if ! kubectl --context "${CTX}" get deployment slow-app >/dev/null 2>&1; then
    bad "slow-app deployment not found"
    echo
    echo "[check] $PASS passed, $FAIL failed"
    exit 1
fi

DESIRED=$(kubectl --context "${CTX}" get deployment slow-app -o jsonpath='{.spec.replicas}')
READY=$(kubectl --context "${CTX}" get deployment slow-app -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [ "${READY:-0}" = "$DESIRED" ]; then
    ok "slow-app deployment fully Ready ($READY/$DESIRED)"
else
    bad "slow-app deployment not fully Ready (ready: ${READY:-0}, desired: $DESIRED)"
fi

POD=$(kubectl --context "${CTX}" get pods -l app=slow-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "${POD:-}" ]; then
    bad "no slow-app pod found"
else
    RESTARTS_BEFORE=$(kubectl --context "${CTX}" get pod "${POD}" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo 0)
    echo "[check] watching for new restarts over 30s (restarts so far: ${RESTARTS_BEFORE:-0})..."
    sleep 30
    POD_AFTER=$(kubectl --context "${CTX}" get pods -l app=slow-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    RESTARTS_AFTER=$(kubectl --context "${CTX}" get pod "${POD_AFTER:-$POD}" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "${RESTARTS_BEFORE:-0}")
    if [ "${RESTARTS_AFTER:-0}" = "${RESTARTS_BEFORE:-0}" ]; then
        ok "no new restarts in the last 30s (steady at ${RESTARTS_AFTER:-0})"
    else
        bad "still restarting (${RESTARTS_BEFORE:-0} -> ${RESTARTS_AFTER:-0}) - livenessProbe is still too aggressive"
    fi
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] slow-app is stable - probe timing looks fixed."
    exit 0
else
    exit 1
fi
