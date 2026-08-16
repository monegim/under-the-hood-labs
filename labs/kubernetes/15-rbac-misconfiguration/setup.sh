#!/usr/bin/env bash
# Lab 15 — RBAC Misconfiguration — setup.sh
#
# Creates a single-node kind cluster, a ServiceAccount "deploy-bot", and a
# Pod running under that ServiceAccount that continuously calls the API
# server directly (curl + its own mounted token, no kubectl binary needed
# — keeps the image tiny and the pull fast) to list Deployments in the
# default namespace — with no Role or RoleBinding granted, so every
# attempt is denied.
#
# Safe/idempotent: deletes any pre-existing "k8s15" cluster first.
set -euo pipefail

CLUSTER=k8s15
CTX="kind-${CLUSTER}"

echo "[1/4] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/4] Creating single-node kind cluster '${CLUSTER}'..."
kind create cluster --name "${CLUSTER}"

echo "[3/4] Creating ServiceAccount 'deploy-bot' (no Role/RoleBinding yet)..."
kubectl --context "${CTX}" create serviceaccount deploy-bot

echo "[4/4] Deploying deploy-bot Pod (polls the API server directly every 5s)..."
cat <<'EOF' | kubectl --context "${CTX}" apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: deploy-bot
spec:
  serviceAccountName: deploy-bot
  containers:
    - name: deploy-bot
      image: curlimages/curl:latest
      command:
        - sh
        - -c
        - |
          while true; do
            curl -s \
              --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
              -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
              https://kubernetes.default.svc/apis/apps/v1/namespaces/default/deployments
            echo
            sleep 5
          done
EOF
kubectl --context "${CTX}" wait --for=condition=Ready pod/deploy-bot --timeout=120s

echo
echo "Done. Give it a few seconds, then check the Pod's own logs:"
echo "  kubectl --context ${CTX} logs deploy-bot --since=6s"
