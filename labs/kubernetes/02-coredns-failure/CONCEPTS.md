# Lab 2 — Concept: CoreDNS Is Just a DNS Server Reading Kubernetes Objects as Zone Data

## What's actually going on

CoreDNS is a general-purpose, plugin-chain DNS server — nothing about it
is Kubernetes-specific at its core. What makes it "the cluster DNS" is
the `kubernetes` plugin, which watches the API server for Service and Pod
objects and answers queries under `cluster.local` (or whatever domain the
cluster is configured with) by synthesizing DNS records from that live
object state, rather than reading a static zone file. Every other
CoreDNS plugin runs as an ordinary DNS server would: `forward` sends
non-cluster queries upstream to some resolver, `cache` caches answers,
`log`/`errors` handle observability. The whole thing is configured by one
plain-text file, the Corefile, parsed once at process startup — there is
no live-reload; a `ConfigMap` change only takes effect after the pods
restart (which is exactly why the fix in this lab, and the real fix for
any Corefile change, ends with `kubectl rollout restart deployment
coredns`).

The main lab's failure — `forward . 192.0.2.53:53` — is a config that's
syntactically valid but semantically wrong: CoreDNS starts fine, accepts
every incoming query, and for anything it doesn't already know the answer
to (which includes essentially everything, since even in-cluster Service
names still get evaluated against the plugin chain), it tries to forward
to an address that will never respond, and eventually gives up and
returns `SERVFAIL` or times out client-side. This is why direct pod-IP
connectivity is unaffected the entire time: CoreDNS's failure is
completely orthogonal to the CNI/kube-proxy data path that Lab 1 and the
Kubernetes Internals lab exercise — packets between pods flow exactly as
before, because nothing about the actual network changed. Only the
"translate a name into an IP" step is broken, which is precisely why
"reachable by IP, unreachable by name" is such a clean, specific
diagnostic signature: it's not evidence of *any* network problem, it's
evidence of specifically *this* one.

Challenge A and Challenge B are two structurally different failures that
produce a similarly-total DNS outage but at completely different
lifecycle stages. A Corefile with an unrecognized directive fails at
*parse time* — the process can't even start, so every replica
crash-loops identically and forever until the ConfigMap is fixed; no
query is ever actually attempted. Scaling the Deployment to zero doesn't
touch config or code at all — it removes the workload from existence,
which cascades into the `kube-dns` Service having zero endpoints (the
same REJECT-on-no-endpoints mechanism as any other Service). Three
different root causes — bad upstream target, invalid config syntax, zero
replicas — all present as "DNS is broken cluster-wide," and each one has
a single, different `kubectl` command (`logs`, `logs --previous`, `get
deployment`) that identifies it immediately, which is the whole point of
practicing all three side by side.

## Where this shows up in the real world

CoreDNS `ConfigMap` edits are a genuinely common, high-blast-radius
change in real clusters — teams add custom `forward` rules for corporate
internal domains ("route `*.corp.internal` to our internal resolver"),
stub-domain configuration for hybrid-cloud DNS, or rewrite rules for
service mesh integration, and a typo or a resolver that later goes away
takes down cluster-wide DNS instantly and silently, because nothing about
the CoreDNS pods themselves looks unhealthy. Crash-looping CoreDNS after
a config change is one of the most common "someone edited the ConfigMap
and didn't restart/didn't validate first" incidents; teams sometimes
manage the Corefile via GitOps/Helm specifically because a bad manual
`kubectl edit` on this one object can take down an entire cluster's name
resolution in seconds.

## Go deeper

- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/ — the official guide to customizing the CoreDNS Corefile safely, including the forward/stub-domain patterns this lab breaks.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/debug/debug-cluster/dns-debugging-resolution/ — the official DNS-debugging-in-cluster walkthrough (creating a debug pod, `nslookup`, checking CoreDNS logs).
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/debug/ — general troubleshooting task index this lab's methodology follows.
- **Website/blog:** Learnk8s blog — https://learnk8s.io/blog — has practical posts on Kubernetes networking and DNS failure diagnosis.
- **YouTube:** That DevOps Guy (Marcel Dempers) — https://www.youtube.com/@MarcelDempers — hands-on CoreDNS/cluster-DNS internals and troubleshooting videos.
