#!/usr/bin/env bash
# Lab 6 — Node Under Memory Pressure — setup.sh
#
# Creates a kind cluster, deploys a BestEffort "canary" pod, then deploys
# a BestEffort memory-hog pod (stress-ng) sized dynamically at MEM_PERCENT
# of the node container's own total memory (read from /proc/meminfo
# inside the node), and waits to see kubelet evict the canary.
#
# SAFETY: a kind node is a Docker container with no memory limit by
# default - it shares your host's real memory. This script prints the
# computed target and caps it via MEM_PERCENT before doing anything. If
# you're on a memory-constrained machine, lower MEM_PERCENT below.
#
# Safe/idempotent: deletes any pre-existing "k8s06" cluster first.
set -euo pipefail

CLUSTER=k8s06
CTX="kind-${CLUSTER}"
NODE="${CLUSTER}-control-plane"
MEM_PERCENT=80   # % of the node container's total memory to allocate

echo "[1/5] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/5] Creating kind cluster '${CLUSTER}'..."
kind create cluster --name "${CLUSTER}"

echo "[3/5] Checking node memory (this is really your host's memory - review before continuing)..."
TOTAL_KB=$(docker exec "${NODE}" grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MI=$((TOTAL_KB / 1024))
TARGET_MI=$((TOTAL_MI * MEM_PERCENT / 100))
echo "      node container total memory: ${TOTAL_MI}Mi"
echo "      memory-hog target (${MEM_PERCENT}%): ${TARGET_MI}Mi"

echo "[4/5] Deploying BestEffort canary pod (no requests/limits, evicted first on purpose)..."
kubectl --context "${CTX}" run nginx-canary --image=nginx --restart=Never
kubectl --context "${CTX}" wait --for=condition=Ready pod/nginx-canary --timeout=60s

echo "[5/5] Deploying memory-hog pod targeting ${TARGET_MI}Mi..."
cat <<EOF | kubectl --context "${CTX}" apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: memory-hog
spec:
  containers:
    - name: stress
      image: polinux/stress-ng
      args: ["--vm", "1", "--vm-bytes", "${TARGET_MI}M", "--vm-hang", "0"]
EOF

echo
echo "Waiting up to 60s to see if MemoryPressure develops and the canary gets evicted..."
for i in $(seq 1 12); do
    sleep 5
    PRESSURE=$(kubectl --context "${CTX}" get node "${NODE}" -o jsonpath='{.status.conditions[?(@.type=="MemoryPressure")].status}' 2>/dev/null || true)
    echo "      [$((i*5))s] MemoryPressure=${PRESSURE:-unknown}"
    if [ "$PRESSURE" = "True" ]; then
        break
    fi
done

echo
echo "Done. Check:"
echo "  kubectl --context ${CTX} describe node ${NODE} | grep -A1 MemoryPressure"
echo "  kubectl --context ${CTX} get pods -o wide"
