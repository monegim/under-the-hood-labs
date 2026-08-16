# Lab 18 — Concept: Kubelet Client Certificates and the Node Authorizer

## What's actually going on

Every kubelet in a kubeadm-bootstrapped cluster (which includes every
`kind` cluster) authenticates to the API server using a client
certificate whose Common Name follows the pattern
`system:node:<node-name>`, in the organization `system:nodes`. This
isn't just an identity label — Kubernetes ships a dedicated authorization
plugin, the Node authorizer, whose entire job is enforcing that a kubelet
presenting that identity can only read/write objects related to *its
own* node (its own Node object, pods scheduled to it, etc.), not
arbitrary cluster state. kubeadm sets up automatic rotation for this
cert by default (`--rotate-certificates`): kubelet periodically requests
a fresh one before the current one expires, and on disk this shows up as
a growing set of timestamped cert files under `/var/lib/kubelet/pki/`
with a symlink, `kubelet-client-current.pem`, always pointed at whichever
one is currently active. That symlink indirection is exactly what this
lab manipulates — repointing it at a different file is a legitimate,
observable way to simulate "rotation left the node with a bad cert,"
without needing to wait for or fake an actual rotation cycle.

The three failures in this lab map onto three genuinely distinct stages
a TLS mutual-auth connection goes through, in order: first, does the
presented certificate chain back to a CA the server trusts at all (trust
chain — Challenge B fails exactly here, "signed by unknown authority");
second, is the certificate currently within its validity window (Step
4's expired cert fails here — trusted issuer, wrong time); third, once
the connection itself is established and the server knows *who* is
asking (from the cert's CN), is that identity authorized to do what it's
asking (Challenge A fails here — trusted issuer, valid window, wrong
subject, rejected by the Node authorizer specifically). The first two
are TLS-layer failures — the connection itself never completes, and
`kubectl` and the API server logs will show a handshake-level error.
The third is an application-layer failure — the TLS handshake succeeds
completely, a request goes through, and it's Kubernetes' own
authorization logic (not the TLS library) that says no.

This is also why `kubectl get nodes` alone can't distinguish any of
these from each other, or from a genuinely dead node: it only shows the
Node object's `status.conditions`, which the API server populates from
"has this kubelet reported in recently" — every one of these failures,
plus a hard node crash, plus a network partition, all produce the same
`NotReady`/`Unknown` from that one vantage point. The actual
differentiating evidence only exists on the node itself, in kubelet's
own logs, because kubelet is the side that's actually attempting the
connection and seeing exactly why it's being rejected.

## Where this shows up in the real world

Certificate rotation failures are a real, if infrequent, source of
mysterious `NotReady` nodes in production kubeadm clusters — a node
whose clock has drifted enough to fall outside a cert's validity window,
a manual node repair or image rebuild that clobbers
`/var/lib/kubelet/pki/` without understanding the rotation layout, or
kubelet being down across an entire rotation window (long enough that
the old cert expires before kubelet comes back to renew it) can all
produce exactly this symptom. Because the standard playbook for
`NotReady` usually starts with node-level physical checks (disk, memory,
network reachability, `kubectl describe node` for resource pressure),
a certificate-identity problem is easy to miss entirely if nobody thinks
to check kubelet's own logs early — everything about the node "looks"
healthy from every angle except the one that actually matters here.

## Go deeper

- **Website/docs:** Kubernetes official docs — https://kubernetes.io/docs/reference/access-authn-authz/authorization/#node-authorization — the Node authorizer, exactly the mechanism Challenge A runs into.
- **Website/docs:** Kubernetes official docs — https://kubernetes.io/docs/reference/access-authn-authz/kubelet-tls-bootstrapping/#certificate-rotation — official documentation of kubelet client-certificate rotation, the mechanism this whole lab is built around.
- **Website/docs:** Kubernetes official docs — https://kubernetes.io/docs/tasks/debug/ — the general troubleshooting section, useful for placing "check kubelet's own logs, not just kubectl" in the broader debugging workflow.
- **Book:** *Kubernetes in Action* — Marko Lukša — covers the kubelet/API-server authentication model and node lifecycle this lab is exercising.
- **YouTube:** That DevOps Guy (Marcel Dempers) — https://www.youtube.com/@MarcelDempers — hands-on Kubernetes internals content, including certificate and authentication topics.
