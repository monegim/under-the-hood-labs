#!/usr/bin/env bash
# Lab 20 — Scheduler Cannot Place Pod — setup.sh
#
# Creates a single-node kind cluster and a Deployment requesting more CPU
# than the node has, period — a `requests.cpu` value nobody sanity-checked
# against real node capacity. The Pod goes Pending and stays there forever,
# with no error anywhere in its own spec.
#
# Safe/idempotent: deletes any pre-existing "k8s20" cluster first.
set -euo pipefail

CLUSTER=k8s20
CTX="kind-${CLUSTER}"

echo "[1/3] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/3] Creating single-node kind cluster '${CLUSTER}'..."
kind create cluster --name "${CLUSTER}"

echo "[2/3] Waiting for the node to be Ready (and its startup taint removed)..."
kubectl --context "${CTX}" wait --for=condition=Ready node --all --timeout=120s

echo "[3/3] Deploying webapp requesting far more CPU than the node has..."
cat <<EOF | kubectl --context "${CTX}" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      containers:
        - name: webapp
          image: nginx:1.27
          resources:
            requests:
              cpu: "20"
              memory: "256Mi"
EOF

echo
echo "Done. Give it a few seconds, then check:"
echo "  kubectl --context ${CTX} get pods -l app=webapp"
echo "  kubectl --context ${CTX} describe pod -l app=webapp"
