# Lab 10 — Concept: HPA Doesn't Measure Anything Itself, metrics-server Does

## What's actually going on

The `HorizontalPodAutoscaler` controller is, itself, blind. It runs inside
`kube-controller-manager` and every sync interval (default 15s) it asks
the API server for CPU/memory numbers the same way `kubectl top` does: via
the `metrics.k8s.io` aggregated API. That API isn't served by
`kube-apiserver` itself — it's registered by an `APIService` object that
delegates requests to whatever's actually implementing it, which on
almost every cluster is `metrics-server`, a separate Deployment that
polls every kubelet's `/stats/summary` endpoint on a short interval,
aggregates it, and answers `metrics.k8s.io` queries from that in-memory
cache. If `metrics-server` isn't running, the `APIService` registration
either doesn't exist or points at a dead backend, and any request to
`metrics.k8s.io` — from `kubectl top`, from the HPA controller, from
anything — fails the same way: "the server is currently unable to handle
the request." Kind (like a bare `kubeadm` cluster) ships none of this by
default; it's an explicit install step on purpose, because not every
cluster needs it and it has real resource/security cost to run.

Once `metrics-server` exists, it has to actually reach every kubelet over
HTTPS to scrape `/stats/summary`, and that's where kind adds a second,
independent gotcha: kubelet serving certificates are typically
self-signed or signed by a cluster-internal CA that isn't in
metrics-server's default trust store, and more specifically on kind the
certificate's Subject Alternative Names don't include whatever address
metrics-server dials. metrics-server's TLS verification fails, scrapes
never succeed, and the Deployment sits at 0 available replicas (or
Running-but-not-Ready) with `x509` errors in its own logs — a completely
separate failure from "not installed at all," reachable only by actually
reading the pod's logs, not just checking that it exists.
`--kubelet-insecure-tls` disables that verification step entirely
(acceptable on a disposable local `kind` cluster; on a real cluster the
correct fix is making kubelet serving certs verifiable, e.g. via kubelet
serving certificate rotation with an approving controller, not disabling
verification cluster-wide).

Even with `metrics-server` fully healthy, the HPA still needs one more
thing before `ScalingActive` can go `True` for a CPU target: every
container the Deployment's pod template defines has to declare
`resources.requests.cpu`. The HPA's utilization math is `(current usage in
millicores) / (requested millicores) * 100`; without a request, there's no
denominator, and the controller reports the metric unavailable rather
than inventing one. This is a distinct, later failure than "no
metrics-server" — the raw usage number can be right there in `kubectl top
pod` output while the HPA still can't compute anything from it, because
usage-vs-request and usage-vs-nothing are different questions.

## Where this shows up in the real world

"I set up an HPA and it just doesn't scale" is an extremely common early
Kubernetes-adoption ticket, almost always on self-managed or local
clusters where nobody thought to install `metrics-server` because managed
cloud offerings often bundle it. It also resurfaces on clusters that
*had* a working metrics pipeline until `metrics-server`'s pod got evicted
or OOMKilled and nobody noticed — HPAs don't alert when they stop scaling,
they just quietly stop reacting to load, which can mean a service stays
under-provisioned during a real traffic spike with no obvious error
anywhere except `kubectl describe hpa`. The missing-`requests.cpu`
variant shows up constantly in Helm charts and manifests copy-pasted from
tutorials that never set resource requests, especially once someone
bolts an HPA onto a workload that was never designed with them in mind.

## Go deeper

- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/ — the official walkthrough this lab's `php-apache` target is taken from.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/concepts/workloads/autoscaling/ — HPA concepts and how it fits with VPA/cluster autoscaling.
- **Website/docs:** kind docs — https://kind.sigs.k8s.io/docs/ — background on kind's default cluster components (and what it deliberately omits, like `metrics-server`).
- **Book:** *Kubernetes in Action* — Marko Lukša — covers the HPA control loop and the metrics pipeline behind it in depth.
- **YouTube:** That DevOps Guy (Marcel Dempers) — https://www.youtube.com/@MarcelDempers — hands-on videos on HPA and metrics-server internals.
