#!/usr/bin/env bash
# Lab 19 — Image Pull Failure — setup.sh
#
# Creates a single-node kind cluster and a Deployment referencing an
# image tag that doesn't exist on a real, reachable registry (a typo'd
# version tag) — the most common real-world cause of ImagePullBackOff.
#
# Safe/idempotent: deletes any pre-existing "k8s19" cluster first.
set -euo pipefail

CLUSTER=k8s19
CTX="kind-${CLUSTER}"

echo "[1/3] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/3] Creating single-node kind cluster '${CLUSTER}'..."
kind create cluster --name "${CLUSTER}"

echo "[3/3] Deploying webapp with a typo'd image tag..."
kubectl --context "${CTX}" create deployment webapp --image=nginx:1.99.99-nonexistent-tag

echo
echo "Done. Give it a few seconds, then check:"
echo "  kubectl --context ${CTX} get pods -l app=webapp"
echo "  kubectl --context ${CTX} describe pod -l app=webapp"
