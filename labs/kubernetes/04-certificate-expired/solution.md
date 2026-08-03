# Lab 4 — Solutions

## Challenge A — not-yet-valid certificate

**Check:**
```bash
kubectl --context kind-k8s04 -n webhook-demo get secret webhook-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/check-a.crt
openssl x509 -in /tmp/check-a.crt -noout -startdate -enddate
kubectl --context kind-k8s04 -n webhook-demo create configmap test-a-check --from-literal=foo=bar 2>&1
```
`-startdate` shows a `notBefore` in the future (2037). The `kubectl
create` error text says something like `x509: certificate is not yet
valid` — a different phrase from Step 2's `certificate has expired`, even
though both are date-range failures on the exact same field family.

**Diagnosis:** TLS validates a certificate's `notBefore`/`notAfter` range
against the *verifier's* current clock (the API server's, here), not the
certificate issuer's intent. A cert with a `notBefore` in the future
fails for the mirror-image reason an expired one does: right now falls
outside the valid window, just on the early side instead of the late
side. In production this is rarely someone deliberately backdating a
future start date — the realistic cause is significant clock skew
between the machine that issued/loaded the cert and the machine
verifying it (an API server node with an unsynced clock, or an
automation pipeline that generated the cert with an inaccurate system
clock at build time), or a rotation that gets deployed slightly before
its intended activation window.

**Fix:**
```bash
CTX=kind-k8s04
mkdir -p /tmp/lab4-rotate-a
docker run --rm -v /tmp/lab4-rotate-a:/certs -v /tmp/lab4-certs:/oldcerts alpine:3.20 sh -c "
  apk add --no-cache openssl >/dev/null
  openssl genrsa -out /certs/server.key 2048 2>/dev/null
  openssl req -new -key /certs/server.key -subj '/CN=expired-webhook.webhook-demo.svc' -out /certs/server.csr 2>/dev/null
  openssl x509 -req -in /certs/server.csr -CA /oldcerts/ca.crt -CAkey /oldcerts/ca.key -CAcreateserial -days 3650 -out /certs/server.crt 2>/dev/null
"
kubectl --context $CTX -n webhook-demo create secret tls webhook-tls --cert=/tmp/lab4-rotate-a/server.crt --key=/tmp/lab4-rotate-a/server.key --dry-run=client -o yaml | kubectl --context $CTX apply -f -
kubectl --context $CTX -n webhook-demo rollout restart deployment expired-webhook
kubectl --context $CTX -n webhook-demo rollout status deployment expired-webhook --timeout=60s
```

**Lesson:** "certificate expired" and "certificate not yet valid" are
both date-range failures, but read the exact error text before assuming
which side of the window you're on — the fix (reissue with a sane
validity window) is the same either way, but a not-yet-valid cert is a
strong hint to also check for clock skew between the affected machines,
which an expired-cert incident usually doesn't need you to check at all.

---

## Challenge B — caBundle trusts the wrong CA

**Check:**
```bash
kubectl --context kind-k8s04 -n webhook-demo get secret webhook-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -enddate -issuer
kubectl --context kind-k8s04 get validatingwebhookconfigurations expired-cert-demo -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | base64 -d | openssl x509 -noout -subject
kubectl --context kind-k8s04 -n webhook-demo create configmap test-b-check --from-literal=foo=bar 2>&1
```
The serving cert's dates are fine and its `issuer` is `CN=other-ca`. But
the webhook's `caBundle` (what the API server was told to trust) still
points at the original lab CA — a completely different certificate,
`CN` and all. The `kubectl create` error says something like `x509:
certificate signed by unknown authority`, not anything about dates.

**Diagnosis:** the API server validates a webhook's serving certificate
against the specific `caBundle` configured on that
`*WebhookConfiguration` object — not against any general system trust
store, and not against "is this cert valid right now" alone. A perfectly
valid, unexpired certificate still fails verification if it wasn't
signed by (or doesn't chain up to) the CA the caller was told to trust.
This is the single most common real-world webhook-cert incident: someone
rotates the serving certificate (often via cert-manager or a Helm
upgrade) using a **new** CA, and updates the Secret the webhook pod
mounts, but the `caBundle` field on the `ValidatingWebhookConfiguration`/
`MutatingWebhookConfiguration` object is a separate, disconnected piece
of config that has to be updated too — and it's easy to forget because
nothing points you at it directly.

**Fix:**
```bash
CTX=kind-k8s04
CA_B64=$(base64 -w0 /tmp/lab4-certs2/ca2.crt 2>/dev/null || base64 /tmp/lab4-certs2/ca2.crt)
kubectl --context $CTX patch validatingwebhookconfiguration expired-cert-demo \
  --type=json -p "[{\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/caBundle\",\"value\":\"$CA_B64\"}]"
kubectl --context $CTX -n webhook-demo create configmap test-b-fixed --from-literal=foo=bar
```

**Lesson:** an expired-cert error and a wrong-CA error can look
superficially similar ("some TLS thing is wrong with the webhook") but
demand checking two different objects — `openssl x509 -enddate` on the
Secret's cert for expiry, versus comparing the Secret's cert `issuer`
against the `WebhookConfiguration`'s `caBundle` subject for a trust
mismatch. Read the exact x509 error text (`certificate has expired` vs.
`signed by unknown authority`) before deciding which one you're dealing
with — they point at entirely different fixes.
