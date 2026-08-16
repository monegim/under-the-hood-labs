#!/usr/bin/env bash
# Lab 17 — Taints/Tolerations Mismatch — setup.sh
#
# Creates a single-node kind cluster, taints that node NoSchedule (as if
# it were dedicated to a specific workload class, e.g. GPU jobs), then
# deploys a plain Deployment with no matching toleration - so it can
# never be scheduled anywhere and sits permanently Pending.
#
# Safe/idempotent: deletes any pre-existing "k8s17" cluster first.
set -euo pipefail

CLUSTER=k8s17
CTX="kind-${CLUSTER}"
NODE="${CLUSTER}-control-plane"

echo "[1/5] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/5] Creating kind cluster '${CLUSTER}'..."
kind create cluster --name "${CLUSTER}"

echo "[3/5] Tainting the node as if it were dedicated to GPU workloads..."
kubectl --context "${CTX}" taint nodes "${NODE}" dedicated=gpu-workloads:NoSchedule

echo "[4/5] Deploying 'web' with no toleration for that taint..."
cat <<EOF | kubectl --context "${CTX}" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: nginx
EOF

echo "[5/5] Waiting to confirm pods stay Pending..."
sleep 15
kubectl --context "${CTX}" get pods -l app=web -o wide

echo
echo "Done. Pods should be stuck Pending:"
echo "  kubectl --context ${CTX} get pods -l app=web"
echo "  kubectl --context ${CTX} describe pod -l app=web"
echo "  kubectl --context ${CTX} describe node ${NODE} | grep -A1 Taints"
