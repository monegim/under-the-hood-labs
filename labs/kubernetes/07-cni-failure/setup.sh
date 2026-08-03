#!/usr/bin/env bash
# Lab 7 — CNI Failure — setup.sh
#
# Creates a kind cluster with a deliberately tiny pod subnet (/27, ~29-30
# usable addresses on the single node) so pod-IP exhaustion is reachable
# with a handful of pods instead of hundreds. Scales a Deployment of
# "pause" containers up until new pods stop getting IPs and stay
# ContainerCreating.
#
# Safe/idempotent: deletes any pre-existing "k8s07" cluster first.
set -euo pipefail

CLUSTER=k8s07
CTX="kind-${CLUSTER}"

echo "[1/5] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/5] Creating kind cluster '${CLUSTER}' with a tiny /27 pod subnet..."
cat <<EOF | kind create cluster --name "${CLUSTER}" --config -
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  podSubnet: "10.244.0.0/27"
EOF

echo "[3/5] Waiting for the cluster to settle (CoreDNS, kindnetd, etc. all consume IPs from the same range)..."
kubectl --context "${CTX}" -n kube-system wait --for=condition=Ready pod -l k8s-app=kube-dns --timeout=120s || true

echo "[4/5] Deploying the cidr-filler Deployment and scaling it up..."
kubectl --context "${CTX}" create deployment cidr-filler --image=registry.k8s.io/pause:3.9 --replicas=1
kubectl --context "${CTX}" scale deployment cidr-filler --replicas=25

echo "[5/5] Waiting to see pods stop getting IPs..."
sleep 30
kubectl --context "${CTX}" get pods -o wide

echo
echo "Done. Some 'cidr-filler' pods should be stuck ContainerCreating/Pending:"
echo "  kubectl --context ${CTX} get pods -o wide"
echo "  kubectl --context ${CTX} describe pod -l app=cidr-filler"
