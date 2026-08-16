#!/usr/bin/env bash
# Lab 12 — Admission Webhook Misconfigured — check.sh
#
# Verifies the guard-webhook Deployment/Service are healthy, the
# ValidatingWebhookConfiguration's clientConfig.service.name actually
# matches a real Service, and — the real test — that creating a ConfigMap
# actually succeeds end to end through the webhook.
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 12 — Admission Webhook Misconfigured"
echo

CTX="kind-k8s12"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

AVAILABLE=$(kubectl --context "${CTX}" -n guard get deployment guard-webhook -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)
if [ -n "$AVAILABLE" ] && [ "$AVAILABLE" -ge 1 ] 2>/dev/null; then
    ok "deployment/guard-webhook has an Available replica"
else
    bad "deployment/guard-webhook has no Available replicas"
fi

SVC_NAME=$(kubectl --context "${CTX}" get validatingwebhookconfigurations guard-block-configmaps \
    -o jsonpath='{.webhooks[0].clientConfig.service.name}' 2>/dev/null || true)
if kubectl --context "${CTX}" -n guard get svc "${SVC_NAME:-__missing__}" >/dev/null 2>&1; then
    ok "webhook clientConfig references an existing Service ('${SVC_NAME}')"
else
    bad "webhook clientConfig references '${SVC_NAME:-<empty>}', which does not exist as a Service in 'guard'"
fi

ENDPOINTS=$(kubectl --context "${CTX}" -n guard get endpoints "${SVC_NAME:-guard-webhook}" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
if [ -n "$ENDPOINTS" ]; then
    ok "svc/${SVC_NAME:-guard-webhook} has endpoint(s): $ENDPOINTS"
else
    bad "svc/${SVC_NAME:-guard-webhook} has no endpoints"
fi

echo "[check] attempting a real ConfigMap create through the webhook..."
kubectl --context "${CTX}" delete configmap webhook-probe --ignore-not-found >/dev/null 2>&1
if kubectl --context "${CTX}" create configmap webhook-probe --from-literal=foo=bar >/dev/null 2>&1; then
    ok "ConfigMap create succeeded end-to-end through guard-block-configmaps"
    kubectl --context "${CTX}" delete configmap webhook-probe --ignore-not-found >/dev/null 2>&1
else
    bad "ConfigMap create still fails (webhook still unreachable)"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] the webhook is reachable and ConfigMap creation is healthy cluster-wide."
    exit 0
else
    exit 1
fi
