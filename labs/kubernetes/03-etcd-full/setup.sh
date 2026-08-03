#!/usr/bin/env bash
# Lab 3 — etcd Full (Quota Exceeded) — setup.sh
#
# Creates a kind cluster, lowers etcd's --quota-backend-bytes to 16MiB by
# editing the static pod manifest on the control-plane node (kubelet picks
# up the change automatically and restarts etcd), then fills etcd with
# junk ConfigMaps until the NOSPACE alarm actually triggers.
#
# Best-effort simulation: kind's single-node etcd has no realistic way to
# organically hit a 2GiB quota in a lab session, so this lowers the quota
# instead of raising the data volume to match production scale. See
# README.md's "Honesty note" for details.
#
# Safe/idempotent: deletes any pre-existing "k8s03" cluster first.
set -euo pipefail

CLUSTER=k8s03
CTX="kind-${CLUSTER}"
NODE="${CLUSTER}-control-plane"
QUOTA_BYTES=16777216   # 16MiB

echo "[1/6] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/6] Creating kind cluster '${CLUSTER}'..."
kind create cluster --name "${CLUSTER}"

echo "[3/6] Lowering etcd's --quota-backend-bytes to ${QUOTA_BYTES} bytes on ${NODE}..."
docker exec "${NODE}" bash -c "
  set -e
  if ! grep -q quota-backend-bytes /etc/kubernetes/manifests/etcd.yaml; then
    sed -i -E 's/^([[:space:]]*)- etcd\$/&\n\1- --quota-backend-bytes=${QUOTA_BYTES}/' /etc/kubernetes/manifests/etcd.yaml
  fi
"

echo "[4/6] Waiting for etcd to restart with the new quota and the API server to recover..."
sleep 15
kubectl --context "${CTX}" wait --for=condition=Ready pod -n kube-system -l component=etcd --timeout=120s
kubectl --context "${CTX}" get nodes >/dev/null

ETCD_POD=$(kubectl --context "${CTX}" -n kube-system get pods -l component=etcd -o jsonpath='{.items[0].metadata.name}')
ETCDCTL_ARGS="--endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"

echo "[5/6] Confirming the new quota took effect..."
kubectl --context "${CTX}" -n kube-system exec "${ETCD_POD}" -- etcdctl ${ETCDCTL_ARGS} endpoint status --write-out=table

echo "[6/6] Filling etcd with ~256KB ConfigMaps until the NOSPACE alarm triggers..."
i=0
MAX_ITER=300
while [ "$i" -lt "$MAX_ITER" ]; do
    DATA=$(head -c 200000 /dev/urandom | base64 | tr -d '\n')
    kubectl --context "${CTX}" create configmap "etcdfull-${i}" --from-literal=data="${DATA}" -l lab=etcd-full >/dev/null 2>&1 || true
    i=$((i+1))

    if [ $((i % 5)) -eq 0 ]; then
        ALARM=$(kubectl --context "${CTX}" -n kube-system exec "${ETCD_POD}" -- etcdctl ${ETCDCTL_ARGS} alarm list 2>/dev/null || true)
        if echo "$ALARM" | grep -q NOSPACE; then
            echo "      NOSPACE alarm triggered after ${i} ConfigMaps."
            break
        fi
        echo "      ...${i} ConfigMaps created, no alarm yet"
    fi
done

echo
echo "Done. Checking final state:"
kubectl --context "${CTX}" -n kube-system exec "${ETCD_POD}" -- etcdctl ${ETCDCTL_ARGS} alarm list
echo
echo "Try a write - it should fail:"
echo "  kubectl --context ${CTX} create configmap post-alarm-test --from-literal=foo=bar"
