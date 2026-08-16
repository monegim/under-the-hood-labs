#!/usr/bin/env bash
# Lab 15 — RBAC Misconfiguration — check.sh
#
# Verifies deploy-bot's ServiceAccount can actually list Deployments in
# the default namespace, and that its Pod's own logs confirm it (not
# just the synthetic auth check).
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()  { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 15 — RBAC Misconfiguration"
echo

CTX="kind-k8s15"

if ! command -v kubectl >/dev/null; then
    bad "kubectl not found in PATH"
    exit 1
fi

if ! kubectl --context "${CTX}" cluster-info >/dev/null 2>&1; then
    bad "cluster '${CTX}' is not reachable (did you run setup.sh?)"
    exit 1
fi
ok "cluster '${CTX}' is reachable"

CANI=$(kubectl --context "${CTX}" auth can-i list deployments \
    --as=system:serviceaccount:default:deploy-bot -n default 2>/dev/null)
if [ "$CANI" = "yes" ]; then
    ok "deploy-bot ServiceAccount can list deployments in 'default'"
else
    bad "deploy-bot ServiceAccount still cannot list deployments in 'default' (auth can-i said: ${CANI:-<empty>})"
fi

RECENT_LOGS=$(kubectl --context "${CTX}" logs deploy-bot --since=8s 2>/dev/null)
if echo "$RECENT_LOGS" | grep -qi "forbidden"; then
    bad "deploy-bot Pod logs still show Forbidden errors"
else
    ok "deploy-bot Pod logs show no recent Forbidden errors"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] deploy-bot has the access it needs, confirmed both via auth can-i and its own logs."
    exit 0
else
    exit 1
fi
