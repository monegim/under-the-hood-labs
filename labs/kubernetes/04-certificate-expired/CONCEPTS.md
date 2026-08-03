# Lab 4 — Concept: Webhooks Are Just TLS Clients the API Server Trusts On Your Terms

## What's actually going on

A `ValidatingWebhookConfiguration` or `MutatingWebhookConfiguration`
doesn't run inside the API server — it tells the API server "for
requests matching these rules, before you finish processing them, make
an HTTPS call out to this Service and ask it what to do." That HTTPS
call is a real TLS connection like any other: the API server acts as a
TLS client, the webhook's backend Pod acts as a TLS server presenting a
certificate, and the API server validates that certificate against the
specific `caBundle` bytes configured on the webhook object — not against
any general system CA trust store, and not against whether the
certificate is "generally fine." This is a deliberately narrow trust
model (you're explicitly telling Kubernetes which CA is allowed to vouch
for this one webhook), and it means two independent things both have to
be true for a call to succeed: the certificate must be currently valid
(within its `notBefore`/`notAfter` window, whatever hostname it claims
matches what the API server dialed), and it must chain up to whatever CA
bytes are sitting in that webhook's `caBundle` field.

TLS's `notBefore`/`notAfter` check is evaluated against the verifying
party's clock at connection time, which is why "expired" and "not yet
valid" are mirror-image failures of the exact same mechanism: the
current time falls outside a fixed window, on the late side or the early
side respectively. An expired cert is almost always a rotation that
silently stopped happening — a cert-manager `Certificate` resource whose
issuer broke, a cron job that used to reissue every 90 days that got
disabled or started failing quietly. A not-yet-valid cert is rarer and
usually points somewhere different: real clock skew between the system
that generated the certificate and the system now verifying it, which is
worth explicitly checking (`date` on both sides) rather than assuming
it's "the same kind of bug" as expiry.

The `caBundle` mismatch (Challenge B) is a structurally different
failure from either date problem, and arguably the most common real
one: a serving certificate can be perfectly within its valid window and
still fail, because the API server isn't checking "is this a valid
certificate in general," it's checking "is this the specific certificate
(or a descendant of the specific CA) I was told to trust for this exact
webhook." Rotating a webhook's serving certificate under a **new** CA
without also patching every `*WebhookConfiguration.webhooks[].
clientConfig.caBundle` that references it produces exactly this: a
healthy, current certificate that the API server correctly refuses to
trust, because trust here is pinned per-object, not inherited from
anywhere else. `failurePolicy: Fail` (used throughout this lab) is what
turns any of these three failures into a hard block on matching
requests, rather than a logged-and-ignored warning — a deliberate
security choice (never silently skip a policy check) that also means a
single stale/mismatched cert can take down every matching API request
cluster-wide until it's fixed.

## Where this shows up in the real world

Custom admission webhooks are extremely common in production clusters —
policy engines (OPA Gatekeeper, Kyverno), service mesh sidecar injectors
(Istio, Linkerd), and cert-manager's own webhook are all implemented this
way. Nearly all of them are designed to have their TLS lifecycle managed
automatically (cert-manager issuing and renewing the cert, a Helm chart's
post-install hook regenerating a self-signed one), which means the
webhook's own certificate is one more automated process that can quietly
break: an issuer misconfiguration, a stuck renewal, an RBAC change that
breaks the renewal job's permissions. Because most of these webhooks are
deployed with `failurePolicy: Fail` for safety (better to block a
request than silently skip a security policy), an expired or
mistrusted webhook certificate has taken down entire clusters' ability to
create the resource types it guards — Pod creation cluster-wide, in the
worst documented cases, when the webhook in question watches Pods.

## Go deeper

- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/ — the authoritative reference for how admission webhooks, `caBundle`, and `failurePolicy` actually work.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/tls/managing-tls-in-a-cluster/ — the CSR API and cluster certificate management, relevant background for the "real" kubelet-cert-rotation case this lab deliberately doesn't reproduce directly.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/debug/ — general troubleshooting task index this lab's diagnostic sequence follows.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man1/openssl-x509.1.html — `openssl x509` reference for `-enddate`/`-startdate`/`-issuer`, the exact flags used throughout this lab.
- **YouTube:** That DevOps Guy (Marcel Dempers) — https://www.youtube.com/@MarcelDempers — hands-on Kubernetes admission controller and TLS/certificate videos.
