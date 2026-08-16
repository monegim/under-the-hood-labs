#!/usr/bin/env bash
# Lab 18 — Kubelet Client Certificate Rotation Failure — check.sh
#
# Verifies the node is back to Ready=True from the API server's
# perspective, and that kubelet-client-current.pem points at a
# currently-valid (non-expired) certificate. Exits 0 only if both hold.
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 18 — Kubelet Client Certificate Rotation Failure"
echo

CTX="kind-k8s18"
NODE="k8s18-control-plane"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

READY=$(kubectl --context "${CTX}" get node "${NODE}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
if [ "${READY}" = "True" ]; then
    ok "node '${NODE}' is Ready"
else
    bad "node '${NODE}' is not Ready (status: '${READY:-unknown}')"
fi

echo "[check] checking kubelet-client-current.pem is not expired..."
if docker exec "${NODE}" bash -c '
  set -e
  TARGET=$(readlink -f /var/lib/kubelet/pki/kubelet-client-current.pem)
  openssl x509 -in "$TARGET" -noout -checkend 0
' >/dev/null 2>&1; then
    ok "kubelet client certificate is currently valid (not expired)"
else
    bad "kubelet client certificate is expired or missing"
fi

echo "[check] checking recent kubelet logs for certificate/auth errors..."
if docker exec "${NODE}" bash -c "journalctl -u kubelet --no-pager -n 50 2>/dev/null | grep -qiE 'certificate has expired|x509|unauthorized'"; then
    bad "recent kubelet logs still show certificate/auth errors"
else
    ok "no recent certificate/auth errors in kubelet logs"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] node is healthy - kubelet is authenticating to the API server normally."
    exit 0
else
    exit 1
fi
