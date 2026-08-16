#!/usr/bin/env bash
# Lab 19 — Image Pull Failure — check.sh
#
# Verifies the webapp Deployment has a Running, Ready Pod pulling a real
# image — the ImagePullBackOff/ErrImagePull/ErrImageNeverPull incident is
# actually resolved, not just retried into a different failure.
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 19 — Image Pull Failure"
echo

CTX="kind-k8s19"

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

BAD_STATE=$(kubectl --context "${CTX}" get pods -l app=webapp -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}' 2>/dev/null || true)
if echo "$BAD_STATE" | grep -qiE "ImagePull|ErrImage"; then
    bad "a webapp Pod is still stuck in an image-pull failure state: ${BAD_STATE}"
else
    ok "no webapp Pod is stuck in an image-pull failure state"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] webapp is Running with a real, pullable image."
    exit 0
else
    exit 1
fi
