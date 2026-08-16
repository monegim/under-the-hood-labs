#!/usr/bin/env bash
# Lab 16 — Probe Misconfiguration — setup.sh
#
# Creates a kind cluster and deploys a small stdlib-only Python HTTP app
# whose single endpoint sometimes takes ~2.5s to respond (simulating real
# load - most requests are fast, some aren't). It's paired with a
# livenessProbe whose timeoutSeconds/periodSeconds/failureThreshold are
# far too aggressive for that occasional latency, so kubelet kills and
# restarts the container every time it happens to hit a slow response -
# even though the app itself never errors and the readinessProbe (given
# sane timing) would have been enough on its own.
#
# Safe/idempotent: deletes any pre-existing "k8s16" cluster first.
set -euo pipefail

CLUSTER=k8s16
CTX="kind-${CLUSTER}"

echo "[1/5] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/5] Creating kind cluster '${CLUSTER}'..."
kind create cluster --name "${CLUSTER}"

echo "[3/5] Creating the slow-app ConfigMap (stdlib-only Python HTTP server)..."
cat <<'PYEOF' > /tmp/lab16-slow-app.py
import http.server, random, time

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # Simulate a real app under real load: about half of requests are
        # fast, the rest take ~2.5s. That's a perfectly normal latency
        # profile for a busy service - and fatal for a 1s probe timeout.
        if random.random() < 0.5:
            time.sleep(2.5)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'ok')

    def log_message(self, fmt, *args):
        pass  # keep container logs quiet - no per-request noise to sift through

http.server.HTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
PYEOF
kubectl --context "${CTX}" create configmap slow-app-script \
  --from-file=app.py=/tmp/lab16-slow-app.py \
  --dry-run=client -o yaml | kubectl --context "${CTX}" apply -f -

echo "[4/5] Deploying slow-app with a too-aggressive livenessProbe..."
cat <<EOF | kubectl --context "${CTX}" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: slow-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: slow-app
  template:
    metadata:
      labels:
        app: slow-app
    spec:
      containers:
        - name: app
          image: python:3.12-slim
          command: ["python3", "/scripts/app.py"]
          ports:
            - containerPort: 8080
          volumeMounts:
            - name: script
              mountPath: /scripts
              readOnly: true
          readinessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 3
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 3
            periodSeconds: 5
            timeoutSeconds: 1
            failureThreshold: 1
      volumes:
        - name: script
          configMap:
            name: slow-app-script
EOF

echo "[5/5] Waiting to see restarts accumulate from the misconfigured livenessProbe..."
sleep 40
kubectl --context "${CTX}" get pods -l app=slow-app

echo
echo "Done. Check restart count and events:"
echo "  kubectl --context ${CTX} get pods -l app=slow-app"
echo "  kubectl --context ${CTX} describe pod -l app=slow-app"
