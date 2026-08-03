#!/usr/bin/env bash
# Lab 2 — CoreDNS Failure — check.sh
#
# Verifies CoreDNS is Running/Ready and can actually resolve the in-cluster
# nginx-svc name (not just that the pods exist). Exits 0 only if a real
# nslookup succeeds.
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 2 — CoreDNS Failure"
echo

CTX="kind-k8s02"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

READY=$(kubectl --context "${CTX}" -n kube-system get deployment coredns -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
DESIRED=$(kubectl --context "${CTX}" -n kube-system get deployment coredns -o jsonpath='{.spec.replicas}' 2>/dev/null || true)
if [ -n "$READY" ] && [ "$READY" = "$DESIRED" ] && [ "$READY" != "0" ]; then
    ok "coredns deployment is fully Ready ($READY/$DESIRED)"
else
    bad "coredns deployment is not fully Ready (ready: '${READY:-0}', desired: '${DESIRED:-unknown}')"
fi

if kubectl --context "${CTX}" get pod nginx >/dev/null 2>&1 && kubectl --context "${CTX}" get svc nginx-svc >/dev/null 2>&1; then
    ok "nginx pod and nginx-svc Service exist"
else
    bad "nginx pod or nginx-svc Service missing"
fi

echo "[check] attempting nslookup of nginx-svc.default.svc.cluster.local (10s timeout)..."
RESULT=$(kubectl --context "${CTX}" run check-dns-"$$" --image=busybox:1.36 --restart=Never --rm -i \
    --command -- timeout 8 nslookup nginx-svc.default.svc.cluster.local 2>&1 || true)

if echo "$RESULT" | grep -q "Address" && ! echo "$RESULT" | grep -qi "can't resolve\|SERVFAIL\|timed out"; then
    ok "in-cluster DNS resolution works"
else
    bad "in-cluster DNS resolution is still broken"
    echo "----- nslookup output -----"
    echo "$RESULT"
    echo "----------------------------"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] CoreDNS is healthy and resolving names correctly."
    exit 0
else
    exit 1
fi
