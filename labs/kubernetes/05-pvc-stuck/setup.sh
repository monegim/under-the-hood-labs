#!/usr/bin/env bash
# Lab 5 — PVC Stuck — setup.sh
#
# Creates a kind cluster (default "standard" StorageClass via
# rancher.io/local-path), confirms dynamic provisioning works with a
# baseline PVC, then creates a second PVC referencing a StorageClass
# ("fast-ssd") that doesn't exist anywhere in the cluster, leaving it
# permanently Pending.
#
# Safe/idempotent: deletes any pre-existing "k8s05" cluster first.
set -euo pipefail

CLUSTER=k8s05
CTX="kind-${CLUSTER}"

echo "[1/5] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/5] Creating kind cluster '${CLUSTER}'..."
kind create cluster --name "${CLUSTER}"

echo "[3/5] Confirming the default StorageClass exists..."
kubectl --context "${CTX}" get storageclass

echo "[4/5] Baseline: confirming dynamic provisioning works normally..."
cat <<EOF | kubectl --context "${CTX}" apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: baseline-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: standard
  resources:
    requests:
      storage: 1Gi
EOF
kubectl --context "${CTX}" wait --for=jsonpath='{.status.phase}'=Bound pvc/baseline-pvc --timeout=60s
echo "      baseline-pvc bound successfully."

echo "[5/5] Creating data-pvc with a nonexistent storageClassName ('fast-ssd')..."
cat <<EOF | kubectl --context "${CTX}" apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: fast-ssd
  resources:
    requests:
      storage: 1Gi
EOF

echo
echo "Done. data-pvc is stuck Pending (references StorageClass 'fast-ssd', which doesn't exist):"
echo "  kubectl --context ${CTX} get pvc data-pvc"
