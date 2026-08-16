#!/usr/bin/env bash
# Lab 11 — Resource Quota Exceeded — setup.sh
#
# Creates a kind cluster, applies a ResourceQuota to a "team-a" namespace,
# deploys two baseline Pods that use up 800m/800Mi of a 1000m/1000Mi
# request quota, then writes (but does not silently swallow the failure
# of) a third Pod manifest that pushes past the remaining headroom.
#
# Safe/idempotent: deletes any pre-existing "k8s11" cluster first.
set -euo pipefail

CLUSTER=k8s11
CTX="kind-${CLUSTER}"

echo "[1/5] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/5] Creating kind cluster '${CLUSTER}'..."
kind create cluster --name "${CLUSTER}"

echo "[3/5] Creating namespace 'team-a' with a ResourceQuota..."
kubectl --context "${CTX}" create namespace team-a --dry-run=client -o yaml | kubectl --context "${CTX}" apply -f -

cat <<EOF | kubectl --context "${CTX}" apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: team-a
spec:
  hard:
    requests.cpu: "1"
    requests.memory: 1000Mi
    limits.cpu: "2"
    limits.memory: 2000Mi
EOF

echo "[4/5] Deploying baseline Pods app-1 and app-2 (800m/800Mi of quota used)..."
for i in 1 2; do
cat <<EOF | kubectl --context "${CTX}" apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: app-${i}
  namespace: team-a
  labels:
    app: app-${i}
spec:
  containers:
    - name: app-${i}
      image: nginx
      resources:
        requests:
          cpu: "400m"
          memory: "400Mi"
        limits:
          cpu: "800m"
          memory: "800Mi"
EOF
done
kubectl --context "${CTX}" -n team-a wait --for=condition=Ready pod/app-1 pod/app-2 --timeout=90s

echo "[5/5] Writing app-3 manifest (requests 300m/300Mi — exceeds remaining quota headroom)..."
cat <<EOF > /tmp/lab11-app-3.yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-3
  namespace: team-a
  labels:
    app: app-3
spec:
  containers:
    - name: app-3
      image: nginx
      resources:
        requests:
          cpu: "300m"
          memory: "300Mi"
        limits:
          cpu: "600m"
          memory: "600Mi"
EOF

echo
echo "Done. Quota headroom is only 200m CPU / 200Mi memory; app-3 asks for 300m/300Mi:"
echo "  kubectl --context ${CTX} -n team-a apply -f /tmp/lab11-app-3.yaml"
echo "(this should fail with 'exceeded quota')"
