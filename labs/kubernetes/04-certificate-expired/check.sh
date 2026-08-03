#!/usr/bin/env bash
# Lab 4 — Expired Certificate — check.sh
#
# Verifies the webhook's serving certificate is currently valid (not
# expired, not not-yet-valid) and that a real ConfigMap create in the
# webhook-demo namespace actually succeeds end-to-end (proving both TLS
# validity AND caBundle trust AND the webhook's own admission response
# are all correct).
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 4 — Expired Certificate"
echo

CTX="kind-k8s04"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

if kubectl --context "${CTX}" -n webhook-demo get deployment expired-webhook >/dev/null 2>&1; then
    READY=$(kubectl --context "${CTX}" -n webhook-demo get deployment expired-webhook -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    if [ "$READY" = "1" ]; then
        ok "webhook deployment is Ready"
    else
        bad "webhook deployment is not Ready"
    fi
else
    bad "webhook deployment does not exist"
fi

CERT=$(kubectl --context "${CTX}" -n webhook-demo get secret webhook-tls -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null || true)
if [ -n "$CERT" ] && command -v openssl >/dev/null; then
    if echo "$CERT" | openssl x509 -noout -checkend 0 >/dev/null 2>&1; then
        ok "webhook serving certificate is currently valid (not expired)"
    else
        bad "webhook serving certificate is expired or not yet valid"
    fi
else
    echo "[check] (skipping openssl cert date check - openssl not available or secret missing)"
fi

echo "[check] attempting a real ConfigMap create in webhook-demo (exercises TLS + caBundle + webhook response)..."
if kubectl --context "${CTX}" -n webhook-demo create configmap check-write-test --from-literal=foo=bar >/dev/null 2>&1; then
    ok "ConfigMap create succeeded - webhook TLS and trust are healthy"
    kubectl --context "${CTX}" -n webhook-demo delete configmap check-write-test >/dev/null 2>&1 || true
else
    bad "ConfigMap create failed - webhook is still blocking requests"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] webhook TLS is healthy - requests succeed end-to-end."
    exit 0
else
    exit 1
fi
