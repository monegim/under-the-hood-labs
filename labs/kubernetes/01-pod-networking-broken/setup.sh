#!/usr/bin/env bash
# Lab 1 — Pod Networking Broken — setup.sh
#
# Creates a kind cluster with the default CNI disabled and Calico installed
# instead (kindnetd does not enforce NetworkPolicy at all), deploys a
# frontend/backend pair in a "shop" namespace, confirms they can talk, then
# applies a default-deny-ingress NetworkPolicy with NO allow rule — leaving
# frontend unable to reach backend.
#
# Safe/idempotent: deletes any pre-existing "k8s01" cluster first.
set -euo pipefail

CLUSTER=k8s01
CTX="kind-${CLUSTER}"
CALICO_VERSION="v3.28.0"

echo "[1/6] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/6] Creating kind cluster '${CLUSTER}' with default CNI disabled..."
cat <<EOF | kind create cluster --name "${CLUSTER}" --config -
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  podSubnet: "192.168.0.0/16"
EOF

echo "[3/6] Installing Calico ${CALICO_VERSION}..."
kubectl --context "${CTX}" apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"

echo "[4/6] Waiting for Calico to be Ready (this can take a minute or two)..."
kubectl --context "${CTX}" -n kube-system wait --for=condition=Ready pod -l k8s-app=calico-node --timeout=180s
kubectl --context "${CTX}" -n kube-system wait --for=condition=Ready pod -l k8s-app=calico-kube-controllers --timeout=180s

echo "[5/6] Deploying frontend/backend in namespace 'shop'..."
kubectl --context "${CTX}" create namespace shop --dry-run=client -o yaml | kubectl --context "${CTX}" apply -f -

kubectl --context "${CTX}" -n shop run backend --image=nginx --restart=Never --labels=app=backend
kubectl --context "${CTX}" -n shop wait --for=condition=Ready pod/backend --timeout=90s
kubectl --context "${CTX}" -n shop expose pod backend --port=80 --name=backend-svc

kubectl --context "${CTX}" -n shop run frontend --image=curlimages/curl --restart=Never --labels=app=frontend --command -- sleep infinity
kubectl --context "${CTX}" -n shop wait --for=condition=Ready pod/frontend --timeout=90s

echo "[6/6] Confirming baseline connectivity, then applying default-deny-ingress (no allow rule)..."
kubectl --context "${CTX}" -n shop exec frontend -- curl -m 5 -sS -o /dev/null -w "baseline curl: HTTP %{http_code}\n" http://backend-svc

cat <<EOF | kubectl --context "${CTX}" apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: shop
spec:
  podSelector: {}
  policyTypes:
    - Ingress
EOF

echo
echo "Done. frontend can no longer reach backend-svc:"
echo "  kubectl --context ${CTX} -n shop exec frontend -- curl -m 3 -sS http://backend-svc"
echo "(this should now hang and time out)"
