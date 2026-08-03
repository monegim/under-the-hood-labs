#!/usr/bin/env bash
# Lab 9 — API Server Unavailable — setup.sh
#
# Creates a kind cluster, confirms kubectl works, then edits the API
# server's static pod manifest on the control-plane node so
# --etcd-servers points at the wrong port, causing the container to
# crash-loop and kubectl to become unreachable - while the node container
# itself, kubelet, and the container runtime all keep running normally.
#
# Safe/idempotent: deletes any pre-existing "k8s09" cluster first.
set -euo pipefail

CLUSTER=k8s09
CTX="kind-${CLUSTER}"
NODE="${CLUSTER}-control-plane"

echo "[1/4] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/4] Creating kind cluster '${CLUSTER}'..."
kind create cluster --name "${CLUSTER}"

echo "[3/4] Confirming kubectl works normally before breaking anything..."
kubectl --context "${CTX}" get nodes

echo "[4/4] Breaking the API server's static pod manifest (--etcd-servers wrong port)..."
docker exec "${NODE}" bash -c "
  sed -i 's#https://127.0.0.1:2379#https://127.0.0.1:23790#' /etc/kubernetes/manifests/kube-apiserver.yaml
"

echo
echo "Waiting a moment for kubelet to notice and restart the API server container..."
sleep 15

echo
echo "Done. kubectl should now be unreachable:"
echo "  kubectl --context ${CTX} get nodes"
echo "(expect a 'connection refused' or timeout error)"
echo
echo "Node-level diagnostics still work, e.g.:"
echo "  docker exec -it ${NODE} bash -c 'crictl ps -a | grep kube-apiserver'"
