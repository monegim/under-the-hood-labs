# Lab 4 — Expired Certificate (Admission Webhook TLS)

## Objective
Break a custom admission webhook by giving its TLS certificate an
already-past expiry date, watch API requests that trigger it fail with an
x509 TLS handshake error, then diagnose and fix it the way you would a
real expired-webhook-cert incident.

## Why this matters
Every call the API server makes to a `ValidatingWebhookConfiguration` or
`MutatingWebhookConfiguration` backend happens over mutual TLS, and that
certificate has an expiry date like any other. When it lapses — most
commonly because whatever was supposed to rotate it (cert-manager, a
Helm chart's pre-install hook, a manual process someone forgot about)
silently stopped doing its job — every API request matching that
webhook's rules starts failing, often with `failurePolicy: Fail` turning
a single stale certificate into a cluster-wide inability to create the
resource type the webhook watches. The error Kubernetes surfaces is
usually a raw TLS handshake message, not anything mentioning
"certificate" in a way that points you at the actual object to check —
recognizing `x509: certificate has expired or is not yet valid` as "go
look at a webhook's TLS cert" rather than "something is wrong with my
manifest" is the whole skill this lab teaches.

> **Design note:** this lab expires a **self-signed webhook certificate**
> rather than the kubelet's own client certificate to the API server.
> Forcing a kind node's real kubelet certificate to expire is invasive —
> it risks breaking the node's ability to talk to the API server at all,
> which overlaps with [Lab 9](../09-api-server-unavailable) and is much
> harder to do safely and reversibly. `kubectl get csr` (shown below) is
> still worth knowing: it's how you'd observe the *real* CSR-based
> lifecycle behind kubelet client/serving cert rotation, even though this
> particular lab's cert isn't issued that way.

## Prerequisites
- Docker installed and running
- `kind`, `kubectl`, and `openssl` (or just Docker — `setup.sh` generates
  certs inside a disposable container so results don't depend on your
  host's OpenSSL/LibreSSL version)

Check first:
```bash
docker version
kind version 2>/dev/null || echo "kind not installed"
kubectl version --client 2>/dev/null || echo "kubectl not installed"
```

Cluster creation (handled for you by `setup.sh`):
```bash
kind create cluster --name k8s04
```

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates the `k8s04` kind cluster, then in a namespace called
`webhook-demo`:
- generates a self-signed CA and a server certificate **already expired**
  (`notAfter` set to yesterday) inside a throwaway container, so the
  result doesn't depend on your host's OpenSSL version
- stores the cert/key in a Secret, mounted into a small Python HTTPS
  server (stdlib-only — it terminates TLS and correctly replies to
  admission requests once TLS actually works, so Steps past the fix
  behave like a real webhook, not just a TLS echo) on port 8443, with a
  `Service` in front of it called `expired-webhook`
- registers a `ValidatingWebhookConfiguration` pointing at that Service,
  with `failurePolicy: Fail`, matching `CREATE` on ConfigMaps in the
  `webhook-demo` namespace, and `caBundle` set to the CA cert generated
  above

## Step 2 — Confirm the symptom
```bash
kubectl --context kind-k8s04 -n webhook-demo create configmap test-cm --from-literal=foo=bar
```
This fails. The error mentions a TLS/x509 problem talking to the webhook
service — not a validation error about your ConfigMap.

## Step 3 — Find which webhook is in the way
```bash
kubectl --context kind-k8s04 get validatingwebhookconfigurations
kubectl --context kind-k8s04 get validatingwebhookconfigurations expired-cert-demo -o yaml
```
This shows the webhook's target Service (`expired-webhook` in
`webhook-demo`), its `failurePolicy: Fail` (why this blocks the request
outright instead of just logging a warning), and its `caBundle`.

## Step 4 — Confirm the cert is actually expired
```bash
kubectl --context kind-k8s04 -n webhook-demo get secret webhook-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/webhook-tls.crt
openssl x509 -in /tmp/webhook-tls.crt -noout -enddate -subject
```
`-enddate` shows a `notAfter` in the past. This is the smoking gun —
proof positive that the cert itself is the problem, not a guess based on
the error message alone.

> For real-world context (not this lab's specific mechanism): kubelet
> client/serving certificates are usually issued and rotated via the
> Kubernetes CSR API. `kubectl get csr` lists any pending or recently
> processed certificate signing requests — worth knowing as the
> equivalent "what's the state of this cert's lifecycle" check when the
> expiring cert in question **is** CSR-API-managed.

## Step 5 — Fix it: reissue and roll the certificate
```bash
CTX=kind-k8s04
mkdir -p /tmp/lab4-rotate
docker run --rm -v /tmp/lab4-rotate:/certs -v /tmp/lab4-certs:/oldcerts alpine:3.20 sh -c "
  apk add --no-cache openssl >/dev/null
  openssl genrsa -out /certs/server.key 2048 2>/dev/null
  openssl req -new -key /certs/server.key -subj '/CN=expired-webhook.webhook-demo.svc' -out /certs/server.csr 2>/dev/null
  openssl x509 -req -in /certs/server.csr -CA /oldcerts/ca.crt -CAkey /oldcerts/ca.key -CAcreateserial \
    -days 3650 -out /certs/server.crt 2>/dev/null
"
kubectl --context $CTX -n webhook-demo create secret tls webhook-tls \
  --cert=/tmp/lab4-rotate/server.crt --key=/tmp/lab4-rotate/server.key \
  --dry-run=client -o yaml | kubectl --context $CTX apply -f -
kubectl --context $CTX -n webhook-demo rollout restart deployment expired-webhook
kubectl --context $CTX -n webhook-demo rollout status deployment expired-webhook --timeout=60s
kubectl --context $CTX -n webhook-demo create configmap test-cm-2 --from-literal=foo=bar
```
This generates a fresh, currently-valid leaf certificate signed by the
**same CA** `setup.sh` already generated (`/tmp/lab4-certs/ca.crt` +
`ca.key`), updates the `webhook-tls` Secret, and restarts the webhook pod so
it picks up the new cert. Because the CA itself didn't change, the
webhook's `caBundle` doesn't need to be touched here — but in a real
rotation that also rotates the CA (not just the leaf cert), updating
`caBundle` on every `*WebhookConfiguration` that trusts it is the step
people most often forget, which is exactly what Challenge B reproduces.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — not-yet-valid instead of expired:**
```bash
bash -c '
CTX=kind-k8s04
docker run --rm -v /tmp/lab4-certs:/certs alpine:3.20 sh -c "
  apk add --no-cache openssl >/dev/null
  openssl genrsa -out /certs/future.key 2048 2>/dev/null
  openssl req -new -key /certs/future.key -subj \"/CN=expired-webhook.webhook-demo.svc\" -out /certs/future.csr 2>/dev/null
  openssl x509 -req -in /certs/future.csr -CA /certs/ca.crt -CAkey /certs/ca.key -CAcreateserial \
    -not_before 20370101000000Z -days 3650 -out /certs/future.crt 2>/dev/null
"
kubectl --context $CTX -n webhook-demo create secret tls webhook-tls --cert=/tmp/lab4-certs/future.crt --key=/tmp/lab4-certs/future.key --dry-run=client -o yaml | kubectl --context $CTX apply -f -
kubectl --context $CTX -n webhook-demo rollout restart deployment expired-webhook
kubectl --context $CTX -n webhook-demo rollout status deployment expired-webhook --timeout=60s
kubectl --context $CTX -n webhook-demo create configmap test-not-yet-valid --from-literal=foo=bar
'
```
Same category of failure, different exact wording. Find the specific
error text that tells you this is "too early" rather than "too late," and
explain a realistic way a cluster ends up with a not-yet-valid cert in
production (hint: it's rarely about the cert's dates being wrong on
purpose).

**Challenge B — caBundle doesn't match the serving cert's CA:**
```bash
bash -c '
CTX=kind-k8s04
docker run --rm -v /tmp/lab4-certs2:/certs alpine:3.20 sh -c "
  apk add --no-cache openssl >/dev/null
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout /certs/ca2.key -out /certs/ca2.crt -subj \"/CN=other-ca\" 2>/dev/null
  openssl genrsa -out /certs/valid2.key 2048 2>/dev/null
  openssl req -new -key /certs/valid2.key -subj \"/CN=expired-webhook.webhook-demo.svc\" -out /certs/valid2.csr 2>/dev/null
  openssl x509 -req -in /certs/valid2.csr -CA /certs/ca2.crt -CAkey /certs/ca2.key -CAcreateserial -days 3650 -out /certs/valid2.crt 2>/dev/null
"
kubectl --context $CTX -n webhook-demo create secret tls webhook-tls --cert=/tmp/lab4-certs2/valid2.crt --key=/tmp/lab4-certs2/valid2.key --dry-run=client -o yaml | kubectl --context $CTX apply -f -
kubectl --context $CTX -n webhook-demo rollout restart deployment expired-webhook
kubectl --context $CTX -n webhook-demo rollout status deployment expired-webhook --timeout=60s
kubectl --context $CTX -n webhook-demo create configmap test-bad-ca --from-literal=foo=bar
'
```
The serving certificate here is perfectly valid (check its dates with
`openssl x509 -enddate -noout` yourself) and the request still fails.
Compare this error's wording to Steps 2-4 and Challenge A — this is a
genuinely different failure category even though it's still "TLS,"
diagnose exactly what doesn't match what.

See `solution.md` only after you've formed your own diagnosis.
