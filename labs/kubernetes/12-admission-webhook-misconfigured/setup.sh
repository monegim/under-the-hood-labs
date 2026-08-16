#!/usr/bin/env bash
# Lab 12 — Admission Webhook Misconfigured — setup.sh
#
# Creates a kind cluster, generates a valid (not expired) self-signed CA +
# server cert inside a throwaway alpine container, deploys a small
# stdlib-only Python HTTPS server as a working admission webhook using
# that cert, confirms it works end to end, then registers a
# ValidatingWebhookConfiguration with failurePolicy: Fail whose
# clientConfig.service.name points at a Service that does NOT exist
# ("guard-webhook-svc" instead of the real "guard-webhook") — blocking
# every ConfigMap create cluster-wide.
#
# Safe/idempotent: deletes any pre-existing "k8s12" cluster first.
set -euo pipefail

CLUSTER=k8s12
CTX="kind-${CLUSTER}"
CERT_DIR=/tmp/lab12-certs

echo "[1/8] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/8] Creating kind cluster '${CLUSTER}'..."
kind create cluster --name "${CLUSTER}"

echo "[3/8] Creating namespace 'guard'..."
kubectl --context "${CTX}" create namespace guard --dry-run=client -o yaml | kubectl --context "${CTX}" apply -f -

echo "[4/8] Generating a valid CA + server certificate (inside alpine, for reproducibility)..."
rm -rf "${CERT_DIR}"
mkdir -p "${CERT_DIR}"
docker run --rm -v "${CERT_DIR}:/certs" alpine:3.20 sh -c '
  set -e
  apk add --no-cache openssl >/dev/null
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout /certs/ca.key -out /certs/ca.crt -subj "/CN=lab12-ca" 2>/dev/null
  openssl genrsa -out /certs/server.key 2048 2>/dev/null
  openssl req -new -key /certs/server.key \
    -subj "/CN=guard-webhook.guard.svc" -out /certs/server.csr 2>/dev/null
  openssl x509 -req -in /certs/server.csr -CA /certs/ca.crt -CAkey /certs/ca.key -CAcreateserial \
    -days 3650 -out /certs/server.crt 2>/dev/null
'

echo "[5/8] Creating the guard-tls Secret and the webhook script ConfigMap..."
kubectl --context "${CTX}" -n guard create secret tls guard-tls \
  --cert="${CERT_DIR}/server.crt" --key="${CERT_DIR}/server.key" \
  --dry-run=client -o yaml | kubectl --context "${CTX}" apply -f -

cat <<'PYEOF' > /tmp/lab12-webhook.py
import ssl, json, http.server

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = json.loads(self.rfile.read(length)) if length else {}
        uid = body.get('request', {}).get('uid', '')
        resp = {
            "apiVersion": "admission.k8s.io/v1",
            "kind": "AdmissionReview",
            "response": {"uid": uid, "allowed": True},
        }
        data = json.dumps(resp).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        pass

httpd = http.server.HTTPServer(('0.0.0.0', 8443), Handler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain('/etc/tls/tls.crt', '/etc/tls/tls.key')
httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
PYEOF
kubectl --context "${CTX}" -n guard create configmap guard-script \
  --from-file=webhook.py=/tmp/lab12-webhook.py \
  --dry-run=client -o yaml | kubectl --context "${CTX}" apply -f -

echo "[6/8] Deploying the webhook server + Service (correctly named 'guard-webhook')..."
cat <<EOF | kubectl --context "${CTX}" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: guard-webhook
  namespace: guard
spec:
  replicas: 1
  selector:
    matchLabels:
      app: guard-webhook
  template:
    metadata:
      labels:
        app: guard-webhook
    spec:
      containers:
        - name: webhook
          image: python:3.12-slim
          command: ["python3", "/scripts/webhook.py"]
          ports:
            - containerPort: 8443
          volumeMounts:
            - name: tls
              mountPath: /etc/tls
              readOnly: true
            - name: script
              mountPath: /scripts
              readOnly: true
      volumes:
        - name: tls
          secret:
            secretName: guard-tls
        - name: script
          configMap:
            name: guard-script
---
apiVersion: v1
kind: Service
metadata:
  name: guard-webhook
  namespace: guard
spec:
  selector:
    app: guard-webhook
  ports:
    - port: 443
      targetPort: 8443
EOF
kubectl --context "${CTX}" -n guard wait --for=condition=Available deployment/guard-webhook --timeout=90s

CA_B64=$(base64 -w0 "${CERT_DIR}/ca.crt" 2>/dev/null || base64 "${CERT_DIR}/ca.crt")

echo "[7/8] Registering the webhook CORRECTLY first, to confirm baseline works..."
cat <<EOF | kubectl --context "${CTX}" apply -f -
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: guard-block-configmaps
webhooks:
  - name: guard-block-configmaps.guard.svc
    admissionReviewVersions: ["v1"]
    sideEffects: None
    failurePolicy: Fail
    clientConfig:
      service:
        name: guard-webhook
        namespace: guard
        path: /validate
        port: 443
      caBundle: ${CA_B64}
    rules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE"]
        resources: ["configmaps"]
EOF
kubectl --context "${CTX}" create configmap baseline-cm --from-literal=foo=bar --dry-run=client -o yaml \
  | kubectl --context "${CTX}" apply -f -
kubectl --context "${CTX}" delete configmap baseline-cm

echo "[8/8] Breaking it: pointing clientConfig.service.name at a Service that doesn't exist..."
kubectl --context "${CTX}" patch validatingwebhookconfigurations guard-block-configmaps --type=json -p='[
  {"op":"replace","path":"/webhooks/0/clientConfig/service/name","value":"guard-webhook-svc"}
]'

echo
echo "Done. ConfigMap creation now fails cluster-wide (webhook Service reference is wrong):"
echo "  kubectl --context ${CTX} -n default create configmap test-cm --from-literal=foo=bar"
