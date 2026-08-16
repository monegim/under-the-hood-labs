#!/usr/bin/env bash
# Lab 13 — StatefulSet PVC Mismatch — setup.sh
#
# Creates a kind cluster, deploys a 3-replica StatefulSet "myapp" with a
# volumeClaimTemplate. Each Pod writes a created-at timestamp file on
# first boot (only if it doesn't already exist) and appends to a
# boot-log.txt on every boot, so scale-down/scale-up PVC reuse can be
# proven from inside the container. No retention policy is set, so the
# default (Retain on both scale and delete) applies.
#
# Safe/idempotent: deletes any pre-existing "k8s13" cluster first.
set -euo pipefail

CLUSTER=k8s13
CTX="kind-${CLUSTER}"

echo "[1/4] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/4] Creating kind cluster '${CLUSTER}'..."
kind create cluster --name "${CLUSTER}"

echo "[3/4] Deploying headless Service 'myapp' + StatefulSet (3 replicas)..."
cat <<EOF | kubectl --context "${CTX}" apply -f -
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  clusterIP: None
  selector:
    app: myapp
  ports:
    - port: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: myapp
spec:
  serviceName: myapp
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: busybox
          command:
            - sh
            - -c
            - |
              if [ ! -f /data/created-at ]; then
                date > /data/created-at
              fi
              echo "boot at \$(date) on \$(hostname)" >> /data/boot-log.txt
              sleep infinity
          volumeMounts:
            - name: data
              mountPath: /data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 100Mi
EOF

echo "[4/4] Waiting for all 3 Pods to be Ready..."
kubectl --context "${CTX}" wait --for=condition=Ready pod/myapp-0 pod/myapp-1 pod/myapp-2 --timeout=120s

echo
echo "Done. myapp-0/1/2 are Running, each with its own Bound PVC:"
echo "  kubectl --context ${CTX} get pods -l app=myapp"
echo "  kubectl --context ${CTX} get pvc"
echo "Try the scale-down/scale-up cycle from the README's Steps 3-4."
