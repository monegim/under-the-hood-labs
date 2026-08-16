# Lab 14 — PodDisruptionBudget Blocking Drain

## Objective
Put a `PodDisruptionBudget` with `minAvailable: 1` in front of a
single-replica Deployment, try to `kubectl drain` the node it's on, and
watch the drain hang/fail — then learn to read `kubectl get pdb`'s
`ALLOWED DISRUPTIONS` column and understand this is the safety mechanism
working exactly as designed, not a bug to force through.

## Why this matters
`kubectl drain` is one of the most common node-maintenance commands in
Kubernetes — upgrading a node, cordoning it for replacement, scaling a
node pool down — and a `PodDisruptionBudget` (PDB) is the thing standing
between "drain proceeds safely" and "drain proceeds and takes your only
replica of something down at the same time as planned node maintenance."
The instinctive reaction when a drain hangs is to assume something is
broken and reach for `kubectl delete pod --grace-period=0 --force` to
push past it — which is exactly the wrong move: that bypasses the
Eviction API entirely, ignores the PDB on purpose, and can turn a
non-event (a drain that correctly waited for more capacity) into a real
outage. Knowing to read `kubectl get pdb` and treat `ALLOWED DISRUPTIONS:
0` as useful information — not an error to route around — is core
on-call judgment.

## Prerequisites
- Docker installed and running
- `kind` and `kubectl`

Check first:
```bash
docker version
kind version 2>/dev/null || echo "kind not installed"
kubectl version --client 2>/dev/null || echo "kubectl not installed"
```

Cluster creation (this is what `setup.sh` runs for you — a 2-node
cluster, control-plane + worker, is needed here so you can drain the
worker without disturbing the control-plane's static pods):
```bash
cat <<'EOF' > /tmp/lab-k8s14-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
EOF
kind create cluster --name k8s14 --config /tmp/lab-k8s14-config.yaml
```

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates the 2-node `k8s14` kind cluster, then deploys `checkout` — a
Deployment with exactly **1 replica** (kind's default taint keeps the
control-plane unschedulable, so it lands on the worker automatically) — a
`Service` in front of it, and a `PodDisruptionBudget` named
`checkout-pdb` with `minAvailable: 1`.

## Step 2 — Confirm the baseline
```bash
kubectl --context kind-k8s14 get pods -l app=checkout -o wide
kubectl --context kind-k8s14 get pdb checkout-pdb
```
One `checkout` Pod, Running, on `k8s14-worker`. `get pdb` shows
`ALLOWED DISRUPTIONS: 0` — with exactly 1 healthy replica and
`minAvailable: 1`, there is zero room to evict anything right now.

## Step 3 — Try to drain the node
```bash
kubectl --context kind-k8s14 drain k8s14-worker --ignore-daemonsets --delete-emptydir-data --timeout=30s
```
This fails/times out. The error mentions the Eviction API refusing
because it would violate a pod's disruption budget — `kubectl drain`
isn't stuck or broken, it asked politely (via the Eviction API, not a
raw delete) and was told no.

## Step 4 — Understand why, don't fight it
```bash
kubectl --context kind-k8s14 get pdb checkout-pdb -o wide
kubectl --context kind-k8s14 describe pdb checkout-pdb
```
`describe` spells it out: `Min available: 1`, `Allowed disruptions: 0`,
and Events showing the eviction attempt was blocked. This is the PDB
doing its job — evicting the only `checkout` Pod would drop available
replicas below `minAvailable`, and the PDB exists specifically to prevent
that. **Do not** reach for `kubectl delete pod --grace-period=0 --force`
here — that would bypass the Eviction API (and the PDB check with it)
entirely, defeating the exact protection you're looking at.

## Step 5 — Fix it: give yourself room, then drain
```bash
kubectl --context kind-k8s14 scale deployment checkout --replicas=2
kubectl --context kind-k8s14 wait --for=condition=Ready pod -l app=checkout --timeout=60s
kubectl --context kind-k8s14 get pdb checkout-pdb
kubectl --context kind-k8s14 drain k8s14-worker --ignore-daemonsets --delete-emptydir-data --timeout=60s
```
With 2 replicas and `minAvailable: 1`, `ALLOWED DISRUPTIONS` becomes `1`
— there's now headroom to evict one Pod while the other keeps serving
traffic, and the drain succeeds cleanly. When maintenance is done:
```bash
kubectl --context kind-k8s14 uncordon k8s14-worker
```
(Scaling back down to 1 replica afterward is a separate, deliberate
choice — not something this lab prescribes.)

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — `maxUnavailable: 0` blocks drain even with 3 replicas:**
```bash
bash -c '
CTX=kind-k8s14
kubectl --context $CTX delete pdb checkout-pdb
kubectl --context $CTX scale deployment checkout --replicas=3
kubectl --context $CTX wait --for=condition=Ready pod -l app=checkout --timeout=60s
cat <<EOF | kubectl --context $CTX apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: checkout-pdb-strict
spec:
  maxUnavailable: 0
  selector:
    matchLabels:
      app: checkout
EOF
kubectl --context $CTX get pdb checkout-pdb-strict
kubectl --context $CTX drain k8s14-worker --ignore-daemonsets --delete-emptydir-data --timeout=30s
'
```
Three replicas this time, plenty of capacity by any normal reading — and
drain still fails. Read `ALLOWED DISRUPTIONS` again and explain, in terms
of `maxUnavailable` specifically (not `minAvailable`), why replica count
doesn't matter here. Is `maxUnavailable: 0` a misconfiguration, or a
legitimate thing someone might actually want?

**Challenge B — drain fails for a completely different reason, no PDB involved:**
```bash
bash -c '
CTX=kind-k8s14
kubectl --context $CTX delete pdb checkout-pdb-strict --ignore-not-found
kubectl --context $CTX run standalone-debug --image=busybox --restart=Never --overrides="{\"spec\":{\"nodeName\":\"k8s14-worker\"}}" -- sleep 3600
kubectl --context $CTX wait --for=condition=Ready pod/standalone-debug --timeout=30s
kubectl --context $CTX drain k8s14-worker --ignore-daemonsets --delete-emptydir-data --timeout=30s
'
```
No `PodDisruptionBudget` exists at all right now (confirm with
`kubectl get pdb`) — yet the drain still refuses to proceed past this
Pod. Read the exact error text; it names a completely different reason
than "disruption budget." Check `kubectl get pod standalone-debug -o
yaml`'s `ownerReferences`, and figure out what `kubectl drain` is
protecting you from this time, and what flag (used deliberately, knowing
what it costs you) would let it proceed anyway.

See `solution.md` only after you've formed your own diagnosis.
