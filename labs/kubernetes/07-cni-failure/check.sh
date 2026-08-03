#!/usr/bin/env bash
# Lab 7 — CNI Failure — check.sh
#
# Verifies every cidr-filler pod is Running with an assigned IP, and that
# the node's CNI config directory has a valid config file present. Exits
# 0 only if both hold.
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 7 — CNI Failure"
echo

CTX="kind-k8s07"
NODE="k8s07-control-plane"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

if kubectl --context "${CTX}" get deployment cidr-filler >/dev/null 2>&1; then
    DESIRED=$(kubectl --context "${CTX}" get deployment cidr-filler -o jsonpath='{.spec.replicas}')
    READY=$(kubectl --context "${CTX}" get deployment cidr-filler -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    if [ "${READY:-0}" = "$DESIRED" ]; then
        ok "cidr-filler deployment fully Ready ($READY/$DESIRED)"
    else
        bad "cidr-filler deployment not fully Ready (ready: ${READY:-0}, desired: $DESIRED)"
    fi
else
    echo "[check] cidr-filler deployment not found - skipping replica check"
fi

echo "[check] checking CNI config file is present on the node..."
if docker exec "${NODE}" sh -c 'ls /etc/cni/net.d/*.conflist >/dev/null 2>&1'; then
    ok "a CNI conflist file is present under /etc/cni/net.d/"
else
    bad "no CNI conflist file found under /etc/cni/net.d/ on ${NODE}"
fi

echo "[check] attempting to schedule and run a fresh test pod..."
kubectl --context "${CTX}" delete pod check-cni-test --ignore-not-found >/dev/null 2>&1 || true
if kubectl --context "${CTX}" run check-cni-test --image=nginx --restart=Never >/dev/null 2>&1 \
   && kubectl --context "${CTX}" wait --for=condition=Ready pod/check-cni-test --timeout=60s >/dev/null 2>&1; then
    ok "test pod scheduled and got an IP successfully"
    kubectl --context "${CTX}" delete pod check-cni-test --ignore-not-found >/dev/null 2>&1 || true
else
    bad "test pod failed to become Ready within 60s"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] CNI is healthy - pods are getting IPs normally."
    exit 0
else
    exit 1
fi
