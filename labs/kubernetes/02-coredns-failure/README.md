# Lab 2 — CoreDNS Failure

## Objective
Break in-cluster DNS resolution with a bad custom `forward` directive in
the CoreDNS `Corefile`, while direct pod-IP connectivity keeps working the
entire time — then diagnose it the way you would on a real cluster.

## Why this matters
"Everything is unreachable by name but reachable by IP" is one of the
clearest DNS-specific signatures in all of distributed systems, and
Kubernetes clusters are no exception: every Service, every
`<name>.<namespace>.svc.cluster.local` lookup, every external hostname a
pod resolves goes through CoreDNS. A single bad edit to the CoreDNS
`ConfigMap` (a typo'd upstream IP in a custom `forward` block, a botched
rollout of a "conditional forwarding" rule for a corporate domain) can
take down name resolution cluster-wide while every other control-plane
component reports perfectly healthy. Knowing to check CoreDNS logs and
`nslookup`/`dig` from inside the cluster — not just "is the pod Running" —
is what separates a two-minute fix from a cluster-wide outage that looks
like fifty unrelated application bugs.

## Prerequisites
- Docker installed and running
- `kind` and `kubectl`

Check first:
```bash
docker version
kind version 2>/dev/null || echo "kind not installed"
kubectl version --client 2>/dev/null || echo "kubectl not installed"
```

Cluster creation (handled for you by `setup.sh`):
```bash
kind create cluster --name k8s02
```

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates the `k8s02` kind cluster, deploys an `nginx` pod + Service,
confirms DNS resolution and connectivity both work, then patches the
`coredns` `ConfigMap` in `kube-system` so its `Corefile` forwards all
non-cluster queries to an address nothing answers on
(`forward . 192.0.2.53:53` — `192.0.2.0/24` is the reserved TEST-NET-1
range, guaranteed to never respond), and restarts the CoreDNS deployment
so it picks up the change.

## Step 2 — Confirm the symptom: names fail, IPs still work
```bash
kubectl --context kind-k8s02 run debug --image=busybox:1.36 --restart=Never --rm -it --command -- sh -c '
  echo "--- nslookup nginx-svc ---";
  nslookup nginx-svc.default.svc.cluster.local || true;
  echo "--- curl by pod IP ---";
  wget -T 3 -qO- http://'"$(kubectl --context kind-k8s02 get pod nginx -o jsonpath='{.status.podIP}')"' || true
'
```
The `nslookup` for the in-cluster Service name times out or errors; the
raw-IP `wget` to the same pod succeeds immediately. Same destination, two
different outcomes — that's the tell that this is specifically a name
resolution problem, not a network reachability problem.

## Step 3 — Check CoreDNS logs
```bash
kubectl --context kind-k8s02 -n kube-system logs -l k8s-app=kube-dns --tail=50
```
Look for `SERVFAIL`, `i/o timeout`, or repeated failed forward attempts —
this confirms CoreDNS is up and processing queries but can't get an answer
back from wherever it's forwarding to.

## Step 4 — Inspect the actual Corefile
```bash
kubectl --context kind-k8s02 -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}'
```
Compare the `forward` line against what a healthy default looks like (it
should forward to `/etc/resolv.conf` unless there's a deliberate custom
rule) — the bad IP is right there once you know to look at this object
instead of assuming CoreDNS itself is broken.

## Step 5 — Fix it
```bash
kubectl --context kind-k8s02 -n kube-system get configmap coredns -o yaml > /tmp/coredns-cm.yaml
sed -i 's/forward \. 192\.0\.2\.53:53/forward . \/etc\/resolv.conf/' /tmp/coredns-cm.yaml
kubectl --context kind-k8s02 apply -f /tmp/coredns-cm.yaml
kubectl --context kind-k8s02 -n kube-system rollout restart deployment coredns
kubectl --context kind-k8s02 -n kube-system rollout status deployment coredns --timeout=60s
```
Re-run the Step 2 `nslookup` — it should now resolve correctly.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — CoreDNS pods crash-looping instead of just misrouting:**
```bash
kubectl --context kind-k8s02 -n kube-system get configmap coredns -o yaml > /tmp/coredns-cm-bad.yaml
sed -i 's/^\( *\)forward \. \/etc\/resolv\.conf/\1forward\n\1garbage-directive-that-does-not-exist/' /tmp/coredns-cm-bad.yaml
kubectl --context kind-k8s02 apply -f /tmp/coredns-cm-bad.yaml
kubectl --context kind-k8s02 -n kube-system rollout restart deployment coredns
kubectl --context kind-k8s02 -n kube-system get pods -l k8s-app=kube-dns -w
```
(Ctrl+C once you see the pod status a few times.) This produces a visibly
different symptom from the main lab — figure out what it is, and why a
syntax-broken Corefile fails this way instead of just resolving wrong.

**Challenge B — no CoreDNS pods running at all:**
```bash
kubectl --context kind-k8s02 -n kube-system get configmap coredns -o yaml > /tmp/coredns-cm-good.yaml
sed -i 's/garbage-directive-that-does-not-exist//; s/^\( *\)forward$/\1forward . \/etc\/resolv.conf/' /tmp/coredns-cm-good.yaml
kubectl --context kind-k8s02 apply -f /tmp/coredns-cm-good.yaml
kubectl --context kind-k8s02 -n kube-system scale deployment coredns --replicas=0
kubectl --context kind-k8s02 -n kube-system get pods -l k8s-app=kube-dns
kubectl --context kind-k8s02 run debug2 --image=busybox:1.36 --restart=Never --rm -it --command -- nslookup nginx-svc.default.svc.cluster.local
```
Compare this failure (no pods at all) to Challenge A (pods present,
crash-looping) and the main lab (pods healthy, resolving wrong) — three
different root causes, three different `kubectl` commands that would
have told you which one you're looking at immediately.

See `solution.md` only after you've formed your own diagnosis.
