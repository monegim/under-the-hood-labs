# Lab 18 — Solutions

## Challenge A — a cert that's still valid, but for the wrong identity

**Check:**
```bash
docker exec k8s18-control-plane journalctl -u kubelet --no-pager | tail -20
```
No certificate-validity or trust-chain error this time — instead
something like `Unauthorized` or `cannot get resource "nodes": Forbidden`
in the log, and the node still shows `NotReady`.

**Diagnosis:** the cert is signed by the real cluster CA and hasn't
expired, so the TLS handshake itself succeeds — the API server accepts
the connection and lets the request through to the authorization layer.
That's exactly where it fails: kubelet authenticates as
`CN=system:node:some-other-node`, and Kubernetes' Node authorizer
specifically checks that a kubelet's claimed identity (`CN=system:node:<name>`)
matches the actual node object it's trying to act as. A cert can be
perfectly valid cryptographically and still be rejected because it's
valid *for someone else*. This is a fundamentally different failure
stage than Step 4's expired cert: that one never got past the TLS
handshake at all (the connection itself was refused); this one completes
the handshake and gets rejected one layer up, at authorization.

**Fix:** same recovery as Step 5 — relink to the last genuinely-issued
cert for this node's real identity:
```bash
docker exec k8s18-control-plane bash -c '
  GOOD=$(ls -t /var/lib/kubelet/pki/kubelet-client-20*.pem 2>/dev/null | head -1)
  ln -sf "$GOOD" /var/lib/kubelet/pki/kubelet-client-current.pem
  systemctl restart kubelet
'
```

**Lesson:** "is this certificate valid" and "is this certificate valid
*for this specific caller*" are two different checks, and a system that
only does the first one (like a naive TLS client-cert setup with no
identity binding) would have accepted this cert with no complaint at
all. Kubernetes' node authorizer exists specifically to close that gap —
which also means an authentication error and an authorization error can
look identical from `kubectl get nodes` alone (`NotReady` either way);
you have to read the actual kubelet log text to know which layer
actually failed.

---

## Challenge B — a cert signed by a CA the cluster doesn't trust at all

**Check:**
```bash
docker exec k8s18-control-plane journalctl -u kubelet --no-pager | tail -20
```
Something like `x509: certificate signed by unknown authority` — and
notably, this shows up immediately, before any request-level error could
even occur.

**Diagnosis:** this cert isn't signed by the cluster's real CA at all —
it's signed by a throwaway CA generated on the spot. The API server's
TLS layer verifies the presented client certificate's signature chain
against the CAs it actually trusts (`/etc/kubernetes/pki/ca.crt`)
*before* anything about identity or authorization is even considered.
An unknown signer fails the handshake outright — earlier and more
fundamentally than both previous failures: Step 4's expired cert was
trusted-but-outdated (right issuer, wrong time window); Challenge A's
cert was trusted-and-current-but-wrong-identity (right issuer, right
time window, wrong subject); this one is untrusted full stop, so the
connection never gets far enough to check either of those things.

**Fix:** identical recovery path once again:
```bash
docker exec k8s18-control-plane bash -c '
  GOOD=$(ls -t /var/lib/kubelet/pki/kubelet-client-20*.pem 2>/dev/null | head -1)
  ln -sf "$GOOD" /var/lib/kubelet/pki/kubelet-client-current.pem
  systemctl restart kubelet
'
```

**Lesson:** the three failures in this lab form a clean ladder, each one
breaking one layer earlier than the last —
trust-chain (Challenge B, fails during the TLS handshake) →
validity-window (Step 4, fails during the TLS handshake) →
identity/authorization (Challenge A, fails after the handshake succeeds,
at the request layer). Same top-level symptom (`NotReady`) every time
from `kubectl get nodes`, three completely different root causes, and
the only way to tell them apart is reading the actual error text from
the component doing the failing — here, kubelet's own logs on the node,
not anything the API server surfaces to `kubectl`.
