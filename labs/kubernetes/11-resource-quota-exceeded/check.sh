#!/usr/bin/env bash
# Lab 11 — Resource Quota Exceeded — check.sh
#
# Verifies the "team-a" namespace's baseline Pods are Running and that a
# fresh Pod fitting inside the quota's remaining headroom can actually be
# created (proving the earlier "exceeded quota" state is resolved, not
# just that the quota object exists).
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 11 — Resource Quota Exceeded"
echo

CTX="kind-k8s11"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

for pod in app-1 app-2; do
    STATUS=$(kubectl --context "${CTX}" -n team-a get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [ "$STATUS" = "Running" ]; then
        ok "pod/$pod is Running"
    else
        bad "pod/$pod is not Running (status: '${STATUS:-not found}')"
    fi
done

if kubectl --context "${CTX}" -n team-a get resourcequota compute-quota >/dev/null 2>&1; then
    ok "resourcequota/compute-quota exists"
else
    bad "resourcequota/compute-quota does not exist"
fi

echo "[check] attempting to create a probe Pod that fits inside remaining quota headroom..."
kubectl --context "${CTX}" -n team-a delete pod quota-probe --ignore-not-found >/dev/null 2>&1

PROBE_OUT=$(cat <<EOF | kubectl --context "${CTX}" apply -f - 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: quota-probe
  namespace: team-a
  labels:
    app: quota-probe
spec:
  containers:
    - name: quota-probe
      image: nginx
      resources:
        requests:
          cpu: "50m"
          memory: "50Mi"
        limits:
          cpu: "100m"
          memory: "100Mi"
EOF
)

if echo "$PROBE_OUT" | grep -q "created\|configured\|unchanged"; then
    ok "probe Pod (50m/50Mi request) was accepted by the quota"
else
    bad "probe Pod was rejected: $PROBE_OUT"
fi

kubectl --context "${CTX}" -n team-a delete pod quota-probe --ignore-not-found >/dev/null 2>&1

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] team-a's baseline workloads are healthy and quota has usable headroom."
    exit 0
else
    exit 1
fi
