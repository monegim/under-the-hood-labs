#!/usr/bin/env bash
# Lab 10 — HPA Not Scaling — setup.sh
#
# Creates a plain kind cluster, deploys the standard k8s HPA-walkthrough
# target (php-apache) with CPU requests/limits set, and creates a
# HorizontalPodAutoscaler targeting it at 50% CPU utilization. Deliberately
# does NOT install metrics-server (kind doesn't ship it), leaving the HPA
# permanently stuck at TARGETS: <unknown>/50%.
#
# Safe/idempotent: deletes any pre-existing "k8s10" cluster first.
set -euo pipefail

CLUSTER=k8s10
CTX="kind-${CLUSTER}"

echo "[1/5] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/5] Creating kind cluster '${CLUSTER}'..."
kind create cluster --name "${CLUSTER}"

echo "[3/5] Deploying php-apache with CPU requests/limits..."
kubectl --context "${CTX}" create deployment php-apache --image=registry.k8s.io/hpa-example \
  --dry-run=client -o yaml | kubectl --context "${CTX}" apply -f -
kubectl --context "${CTX}" patch deployment php-apache --type=json -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/resources","value":{"requests":{"cpu":"200m"},"limits":{"cpu":"500m"}}}
]'
kubectl --context "${CTX}" expose deployment php-apache --port=80
kubectl --context "${CTX}" wait --for=condition=Available deployment/php-apache --timeout=90s

echo "[4/5] Creating a HorizontalPodAutoscaler targeting php-apache (50% CPU, 1-5 replicas)..."
cat <<EOF | kubectl --context "${CTX}" apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: php-apache
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: php-apache
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
EOF

echo "[5/5] Deliberately NOT installing metrics-server. Confirming the break..."
sleep 5
echo "--- kubectl top pods (expected to fail) ---"
kubectl --context "${CTX}" top pods 2>&1 || true
echo "--- kubectl get hpa (expected TARGETS: <unknown>/50%) ---"
kubectl --context "${CTX}" get hpa php-apache

echo
echo "Done. HPA php-apache cannot read CPU metrics (no metrics-server installed):"
echo "  kubectl --context ${CTX} describe hpa php-apache"
