#!/usr/bin/env bash
# Lab 14 — PDB Blocking Drain — setup.sh
#
# Creates a 2-node (control-plane + worker) kind cluster, deploys a
# single-replica "checkout" Deployment (kind's default control-plane taint
# keeps it off the control-plane node automatically) + Service, and a
# PodDisruptionBudget with minAvailable: 1 — leaving zero allowed
# disruptions for the only replica.
#
# Safe/idempotent: deletes any pre-existing "k8s14" cluster first.
set -euo pipefail

CLUSTER=k8s14
CTX="kind-${CLUSTER}"

echo "[1/5] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/5] Creating 2-node kind cluster '${CLUSTER}' (control-plane + worker)..."
cat <<EOF | kind create cluster --name "${CLUSTER}" --config -
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
EOF

echo "[3/5] Deploying checkout (1 replica) + Service..."
kubectl --context "${CTX}" create deployment checkout --image=nginx --replicas=1
kubectl --context "${CTX}" expose deployment checkout --port=80
kubectl --context "${CTX}" wait --for=condition=Available deployment/checkout --timeout=90s

echo "[4/5] Creating PodDisruptionBudget checkout-pdb (minAvailable: 1)..."
cat <<EOF | kubectl --context "${CTX}" apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: checkout-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: checkout
EOF

echo "[5/5] Confirming the break..."
sleep 3
kubectl --context "${CTX}" get pods -l app=checkout -o wide
kubectl --context "${CTX}" get pdb checkout-pdb

echo
echo "Done. checkout has 1 replica and ALLOWED DISRUPTIONS: 0 — draining k8s14-worker will fail:"
echo "  kubectl --context ${CTX} drain k8s14-worker --ignore-daemonsets --delete-emptydir-data --timeout=30s"
