# Lab 2 — Solutions

## Challenge A — syntax-broken Corefile, CoreDNS crash-loops

**Check:**
```bash
kubectl --context kind-k8s02 -n kube-system get pods -l k8s-app=kube-dns
kubectl --context kind-k8s02 -n kube-system logs -l k8s-app=kube-dns --tail=30 --previous
```
Pods cycle through `CrashLoopBackOff`. `logs --previous` (the last
crashed instance's log, since the current one may not have logged
anything yet) shows a Corefile syntax/parse error at startup, not a
runtime DNS failure.

**Diagnosis:** CoreDNS parses its entire `Corefile` at process startup,
before it serves a single query. `garbage-directive-that-does-not-exist`
isn't a plugin CoreDNS knows about, so the parser rejects the whole
config and the process exits immediately — every replica hits this on
every restart attempt, which is exactly what `CrashLoopBackOff` looks
like. This is a fundamentally different failure from the main lab: there,
CoreDNS started fine and ran with a *valid* but *wrong* config (bad
upstream IP); here, the config itself is invalid and the process can't
start at all.

**Fix:**
```bash
kubectl --context kind-k8s02 -n kube-system get configmap coredns -o yaml > /tmp/coredns-cm-fix.yaml
sed -i '/garbage-directive-that-does-not-exist/d' /tmp/coredns-cm-fix.yaml
sed -i 's/^\( *\)forward$/\1forward . \/etc\/resolv.conf/' /tmp/coredns-cm-fix.yaml
kubectl --context kind-k8s02 apply -f /tmp/coredns-cm-fix.yaml
kubectl --context kind-k8s02 -n kube-system rollout restart deployment coredns
kubectl --context kind-k8s02 -n kube-system rollout status deployment coredns --timeout=60s
```

**Lesson:** `CrashLoopBackOff` on CoreDNS specifically means "check the
Corefile syntax first," not "check upstream connectivity" — a bad
directive name fails at parse time, before any query is ever attempted.
`kubectl logs --previous` is essential here since a crash-looping pod's
*current* container may be too new to have logged anything useful yet.

---

## Challenge B — CoreDNS scaled to zero, no pods at all

**Check:**
```bash
kubectl --context kind-k8s02 -n kube-system get deployment coredns
kubectl --context kind-k8s02 -n kube-system get pods -l k8s-app=kube-dns
kubectl --context kind-k8s02 -n kube-system get endpoints kube-dns
```
`get deployment coredns` shows `0/0` desired/ready replicas.
`get pods -l k8s-app=kube-dns` returns nothing at all — not `Pending`, not
`CrashLoopBackOff`, no matching pods exist. `get endpoints kube-dns` (the
Service in front of CoreDNS) shows `<none>`.

**Diagnosis:** the Deployment itself was scaled to zero. There's no
process to crash and no config to be wrong — the workload simply isn't
running. Every DNS query cluster-wide fails identically (immediate
`SERVFAIL` or connection refused to the `kube-dns` ClusterIP, since
`kube-dns`'s Service now has no endpoints either — the same
no-endpoints-means-REJECT mechanism from
[Lab 1](../01-pod-networking-broken) and the
[Kubernetes Internals lab](../../linux/06-kubernetes-internals)).

**Fix:**
```bash
kubectl --context kind-k8s02 -n kube-system scale deployment coredns --replicas=2
kubectl --context kind-k8s02 -n kube-system rollout status deployment coredns --timeout=60s
```

**Lesson:** always check `kubectl get deployment coredns -n kube-system`
(replica counts) before diving into logs or Corefile content — "zero
pods, zero replicas desired" is a one-command diagnosis that rules out
both crash-looping and bad-config scenarios instantly, and is easy to
overlook if you jump straight to `logs` and find nothing to look at.
