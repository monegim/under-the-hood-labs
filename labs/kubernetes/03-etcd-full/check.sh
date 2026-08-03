#!/usr/bin/env bash
# Lab 3 — etcd Full — check.sh
#
# Verifies etcd has no NOSPACE alarm active and that a real write
# (create + delete a ConfigMap) actually succeeds. Exits 0 only if both
# hold.
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 3 — etcd Full"
echo

CTX="kind-k8s03"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

ETCD_POD=$(kubectl --context "${CTX}" -n kube-system get pods -l component=etcd -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$ETCD_POD" ]; then
    bad "no etcd pod found in kube-system"
    exit 1
fi
ok "found etcd pod: $ETCD_POD"

ETCDCTL_ARGS="--endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"

ALARMS=$(kubectl --context "${CTX}" -n kube-system exec "$ETCD_POD" -- etcdctl $ETCDCTL_ARGS alarm list 2>/dev/null || true)
if [ -z "$ALARMS" ]; then
    ok "no etcd alarms active"
else
    bad "etcd alarm(s) still active: $ALARMS"
fi

echo "[check] attempting a real write (create + delete a ConfigMap)..."
if kubectl --context "${CTX}" create configmap check-write-test --from-literal=foo=bar >/dev/null 2>&1; then
    ok "write succeeded"
    kubectl --context "${CTX}" delete configmap check-write-test >/dev/null 2>&1 || true
else
    bad "write failed - etcd quota/alarm likely still blocking writes"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] etcd is healthy - no alarms, writes succeed."
    exit 0
else
    exit 1
fi
