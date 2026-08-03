#!/usr/bin/env bash
# Lab 8 — Ingress Broken — setup.sh
#
# Creates a kind cluster using kind's documented ingress-nginx recipe
# (extraPortMappings for 80/443 + an ingress-ready node label), installs
# ingress-nginx, deploys an nginx backend + Service, then creates an
# Ingress whose backend Service name is deliberately wrong.
#
# Safe/idempotent: deletes any pre-existing "k8s08" cluster first.
set -euo pipefail

CLUSTER=k8s08
CTX="kind-${CLUSTER}"

echo "[1/6] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/6] Creating kind cluster '${CLUSTER}' with ingress port mappings + node label..."
cat <<EOF | kind create cluster --name "${CLUSTER}" --config -
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
EOF

echo "[3/6] Installing ingress-nginx (kind provider manifest)..."
kubectl --context "${CTX}" apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "[4/6] Waiting for the ingress-nginx controller to be Ready (can take a minute)..."
kubectl --context "${CTX}" -n ingress-nginx wait --for=condition=Ready pod \
  -l app.kubernetes.io/component=controller --timeout=180s

echo "[5/6] Deploying nginx backend + Service..."
kubectl --context "${CTX}" run web --image=nginx --restart=Never
kubectl --context "${CTX}" wait --for=condition=Ready pod/web --timeout=60s
kubectl --context "${CTX}" expose pod web --port=80 --name=web-svc

echo "[6/6] Creating web-ingress with a deliberately wrong backend service name..."
cat <<EOF | kubectl --context "${CTX}" apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
spec:
  ingressClassName: nginx
  rules:
    - host: lab8.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web-svc-typo
                port:
                  number: 80
EOF

sleep 5
echo
echo "Done. Requests to the Ingress now get a 503 from ingress-nginx:"
echo '  curl -sS -H "Host: lab8.local" http://localhost/'
