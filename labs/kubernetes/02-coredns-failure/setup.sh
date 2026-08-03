#!/usr/bin/env bash
# Lab 2 — CoreDNS Failure — setup.sh
#
# Creates a plain kind cluster, deploys nginx + a Service, confirms DNS
# resolution and connectivity both work, then patches the CoreDNS
# ConfigMap so it forwards everything to an address that will never
# respond (192.0.2.53 - TEST-NET-1, reserved for documentation, guaranteed
# unroutable), and restarts CoreDNS so the change takes effect.
#
# Safe/idempotent: deletes any pre-existing "k8s02" cluster first.
set -euo pipefail

CLUSTER=k8s02
CTX="kind-${CLUSTER}"

echo "[1/6] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/6] Creating kind cluster '${CLUSTER}'..."
kind create cluster --name "${CLUSTER}"

echo "[3/6] Deploying nginx + Service..."
kubectl --context "${CTX}" run nginx --image=nginx --restart=Never
kubectl --context "${CTX}" wait --for=condition=Ready pod/nginx --timeout=90s
kubectl --context "${CTX}" expose pod nginx --port=80 --name=nginx-svc

echo "[4/6] Confirming baseline DNS resolution works..."
kubectl --context "${CTX}" run debug-baseline --image=busybox:1.36 --restart=Never --rm -it --command -- \
  nslookup nginx-svc.default.svc.cluster.local

echo "[5/6] Backing up the working CoreDNS ConfigMap to /tmp/coredns-cm-original.yaml..."
kubectl --context "${CTX}" -n kube-system get configmap coredns -o yaml > /tmp/coredns-cm-original.yaml

echo "[6/6] Patching CoreDNS's Corefile to forward to an unroutable address..."
kubectl --context "${CTX}" -n kube-system get configmap coredns -o yaml > /tmp/coredns-cm-broken.yaml
sed -i 's/forward \. \/etc\/resolv\.conf/forward . 192.0.2.53:53/' /tmp/coredns-cm-broken.yaml
kubectl --context "${CTX}" apply -f /tmp/coredns-cm-broken.yaml
kubectl --context "${CTX}" -n kube-system rollout restart deployment coredns
kubectl --context "${CTX}" -n kube-system rollout status deployment coredns --timeout=60s

echo
echo "Done. In-cluster DNS resolution is now broken; direct pod-IP connectivity still works."
echo "Try:"
echo "  kubectl --context ${CTX} run debug --image=busybox:1.36 --restart=Never --rm -it --command -- nslookup nginx-svc.default.svc.cluster.local"
echo "(this should now time out / SERVFAIL)"
