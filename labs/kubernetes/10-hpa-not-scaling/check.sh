#!/usr/bin/env bash
# Lab 10 — HPA Not Scaling — check.sh
#
# Verifies metrics-server is installed, healthy, and actually serving data,
# and that the HPA is reading a real CPU metric (not <unknown>). Exits 0
# only if the whole metrics pipeline is functioning end to end.
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 10 — HPA Not Scaling"
echo

CTX="kind-k8s10"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

if kubectl --context "${CTX}" -n kube-system get deployment metrics-server >/dev/null 2>&1; then
    ok "deployment/metrics-server exists in kube-system"
else
    bad "deployment/metrics-server not found in kube-system (did you install it?)"
fi

AVAILABLE=$(kubectl --context "${CTX}" -n kube-system get deployment metrics-server -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)
if [ -n "$AVAILABLE" ] && [ "$AVAILABLE" -ge 1 ] 2>/dev/null; then
    ok "metrics-server has an Available replica"
else
    bad "metrics-server has no Available replicas (check for --kubelet-insecure-tls and pod logs)"
fi

echo "[check] attempting 'kubectl top pods'..."
if kubectl --context "${CTX}" top pods >/dev/null 2>&1; then
    ok "kubectl top pods succeeds (metrics API is serving data)"
else
    bad "kubectl top pods still fails"
fi

CURRENT=$(kubectl --context "${CTX}" get hpa php-apache -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || true)
if [ -n "$CURRENT" ]; then
    ok "hpa/php-apache has a real currentMetrics value (${CURRENT}%)"
else
    bad "hpa/php-apache still has no currentMetrics (TARGETS likely <unknown>)"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] metrics-server is installed and the HPA is reading real CPU metrics."
    exit 0
else
    exit 1
fi
