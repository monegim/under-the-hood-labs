#!/usr/bin/env bash
# Lab 4 — Expired Certificate (Admission Webhook TLS) — setup.sh
#
# Creates a kind cluster, generates a self-signed CA + an already-expired
# server cert inside a throwaway alpine container (so cert generation
# doesn't depend on the host's OpenSSL/LibreSSL version), deploys a small
# stdlib-only Python HTTPS server as a fake admission webhook using that
# cert, and registers a ValidatingWebhookConfiguration pointing at it with
# failurePolicy: Fail.
#
# Safe/idempotent: deletes any pre-existing "k8s04" cluster first.
set -euo pipefail

CLUSTER=k8s04
CTX="kind-${CLUSTER}"
CERT_DIR=/tmp/lab4-certs

echo "[1/7] Removing any pre-existing '${CLUSTER}' cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[2/7] Creating kind cluster '${CLUSTER}'..."
kind create cluster --name "${CLUSTER}"

echo "[3/7] Creating namespace 'webhook-demo'..."
kubectl --context "${CTX}" create namespace webhook-demo --dry-run=client -o yaml | kubectl --context "${CTX}" apply -f -

echo "[4/7] Generating CA + an already-expired server certificate (inside alpine, for reproducibility)..."
rm -rf "${CERT_DIR}"
mkdir -p "${CERT_DIR}"
docker run --rm -v "${CERT_DIR}:/certs" alpine:3.20 sh -c '
  set -e
  apk add --no-cache openssl >/dev/null
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout /certs/ca.key -out /certs/ca.crt -subj "/CN=lab4-ca" 2>/dev/null
  openssl genrsa -out /certs/server.key 2048 2>/dev/null
  openssl req -new -key /certs/server.key \
    -subj "/CN=expired-webhook.webhook-demo.svc" -out /certs/server.csr 2>/dev/null
  # -days -1: notAfter set to yesterday, i.e. already expired at generation time.
  openssl x509 -req -in /certs/server.csr -CA /certs/ca.crt -CAkey /certs/ca.key -CAcreateserial \
    -days -1 -out /certs/server.crt 2>/dev/null
'
echo "      Confirming the generated cert is actually expired:"
openssl x509 -in "${CERT_DIR}/server.crt" -noout -enddate

echo "[5/7] Creating the webhook-tls Secret and the admission-webhook script ConfigMap..."
kubectl --context "${CTX}" -n webhook-demo create secret tls webhook-tls \
  --cert="${CERT_DIR}/server.crt" --key="${CERT_DIR}/server.key" \
  --dry-run=client -o yaml | kubectl --context "${CTX}" apply -f -

cat <<'PYEOF' > /tmp/lab4-webhook.py
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
kubectl --context "${CTX}" -n webhook-demo create configmap webhook-script \
  --from-file=webhook.py=/tmp/lab4-webhook.py \
  --dry-run=client -o yaml | kubectl --context "${CTX}" apply -f -

echo "[6/7] Deploying the webhook server + Service..."
cat <<EOF | kubectl --context "${CTX}" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: expired-webhook
  namespace: webhook-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: expired-webhook
  template:
    metadata:
      labels:
        app: expired-webhook
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
            secretName: webhook-tls
        - name: script
          configMap:
            name: webhook-script
---
apiVersion: v1
kind: Service
metadata:
  name: expired-webhook
  namespace: webhook-demo
spec:
  selector:
    app: expired-webhook
  ports:
    - port: 443
      targetPort: 8443
EOF
kubectl --context "${CTX}" -n webhook-demo wait --for=condition=Available deployment/expired-webhook --timeout=90s

echo "[7/7] Registering the ValidatingWebhookConfiguration (failurePolicy: Fail)..."
CA_B64=$(base64 -w0 "${CERT_DIR}/ca.crt" 2>/dev/null || base64 "${CERT_DIR}/ca.crt")
cat <<EOF | kubectl --context "${CTX}" apply -f -
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: expired-cert-demo
webhooks:
  - name: expired-cert-demo.webhook-demo.svc
    admissionReviewVersions: ["v1"]
    sideEffects: None
    failurePolicy: Fail
    clientConfig:
      service:
        name: expired-webhook
        namespace: webhook-demo
        path: /validate
        port: 443
      caBundle: ${CA_B64}
    rules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE"]
        resources: ["configmaps"]
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: webhook-demo
EOF

echo
echo "Done. ConfigMap creation in the 'webhook-demo' namespace now fails with an expired-certificate TLS error:"
echo "  kubectl --context ${CTX} -n webhook-demo create configmap test-cm --from-literal=foo=bar"
