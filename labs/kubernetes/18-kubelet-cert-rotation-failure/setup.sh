#!/usr/bin/env bash
# Lab 18 — Kubelet Client Certificate Rotation Failure — setup.sh
#
# Creates a kind cluster (kubeadm-bootstrapped, like every kind cluster),
# then on the control-plane node replaces the kubelet's client
# certificate - the one kubelet uses to authenticate itself TO the API
# server, kept at /var/lib/kubelet/pki/kubelet-client-current.pem and
# normally kept fresh by kubelet's own certificate rotation - with an
# already-expired one signed by the cluster's real CA, and restarts
# kubelet. The node process itself stays alive the whole time; it's the
# API server that can no longer authenticate it, which is a different
# failure signature than the node being down.
#
# Safe/idempotent: deletes any pre-existing "k8s18" cluster first.
set -euo pipefail

CLUSTER=k8s18
CTX="kind-${CLUSTER}"
NODE="${CLUSTER}-control-plane"

echo "[1/5] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/5] Creating kind cluster '${CLUSTER}'..."
kind create cluster --name "${CLUSTER}"

echo "[3/5] Confirming the node is Ready before breaking anything..."
kubectl --context "${CTX}" get nodes

echo "[4/5] Confirming kubelet's client cert rotation layout is present..."
if ! docker exec "${NODE}" test -L /var/lib/kubelet/pki/kubelet-client-current.pem; then
    echo "ERROR: /var/lib/kubelet/pki/kubelet-client-current.pem is not the expected" >&2
    echo "       rotating symlink on this node/kubeadm version - this lab's approach" >&2
    echo "       depends on kubeadm's default kubelet client-cert rotation layout." >&2
    exit 1
fi
echo "      OK - kubelet-client-current.pem is a symlink, as expected."

echo "[5/5] Replacing the kubelet client cert with an already-expired one, signed by the real cluster CA..."
docker exec "${NODE}" bash -c '
  set -e
  PKI_DIR=/etc/kubernetes/pki
  KUBELET_PKI=/var/lib/kubelet/pki
  echo "      current cert target: $(readlink -f ${KUBELET_PKI}/kubelet-client-current.pem)"
  openssl genrsa -out /tmp/expired-client.key 2048 2>/dev/null
  openssl req -new -key /tmp/expired-client.key \
    -subj "/O=system:nodes/CN=system:node:'"${NODE}"'" \
    -out /tmp/expired-client.csr 2>/dev/null
  # -days -1: notAfter set to yesterday, i.e. already expired at generation time.
  openssl x509 -req -in /tmp/expired-client.csr \
    -CA ${PKI_DIR}/ca.crt -CAkey ${PKI_DIR}/ca.key -CAcreateserial \
    -days -1 -out /tmp/expired-client.crt 2>/dev/null
  cat /tmp/expired-client.crt /tmp/expired-client.key > ${KUBELET_PKI}/kubelet-client-expired.pem
  echo "      confirming the generated cert is actually expired:"
  openssl x509 -in ${KUBELET_PKI}/kubelet-client-expired.pem -noout -enddate
  ln -sf ${KUBELET_PKI}/kubelet-client-expired.pem ${KUBELET_PKI}/kubelet-client-current.pem
  systemctl restart kubelet
'

echo
echo "Waiting for the API server to stop hearing from this node's kubelet..."
sleep 45
kubectl --context "${CTX}" get nodes

echo
echo "Done. The node should now show NotReady (or Unknown conditions):"
echo "  kubectl --context ${CTX} get nodes"
echo "  kubectl --context ${CTX} describe node ${NODE} | grep -A5 Conditions"
echo "  docker exec ${NODE} journalctl -u kubelet --no-pager | tail -30"
