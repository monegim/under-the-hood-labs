# Lab 17 — Taints/Tolerations Mismatch

## Objective
Taint a node the way you legitimately would for a real reason (reserving
it for a specific workload class), deploy something ordinary without the
matching toleration, and watch it sit `Pending` forever with no error in
the pod spec at all. Learn to read taints and tolerations side by side
to see exactly why, and understand that "remove the taint" and "add a
toleration" are two different fixes with two very different
consequences.

## Why this matters
A `Pending` pod with no obviously-wrong spec is one of the more
frustrating things to debug if you don't know to check the node side of
the equation — the Deployment looks completely fine, the image exists,
resource requests are modest, and yet nothing happens. Taints are a
node-level opt-out ("don't schedule things here unless they specifically
say they're okay with this") and the scheduler enforces them silently:
it doesn't error, it just never picks that node as a candidate. The fix
also isn't always "add a toleration" — sometimes the taint itself is
stale or was applied by mistake, and removing it is the right call
instead. Those two fixes aren't interchangeable: one opens the node back
up to everything, the other keeps the node reserved and only lets your
one workload in.

## Prerequisites
- Docker installed and running
- `kind` and `kubectl`

Check first:
```bash
docker version
kind version 2>/dev/null || echo "kind not installed"
kubectl version --client 2>/dev/null || echo "kubectl not installed"
```

Cluster creation (this is what `setup.sh` runs for you):
```bash
kind create cluster --name k8s17
```

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates the `k8s17` kind cluster, taints its single node
`dedicated=gpu-workloads:NoSchedule` (simulating a node reserved for a
specific workload class), then deploys a plain two-replica `web`
Deployment (`nginx`, no toleration) that can't be scheduled anywhere.

## Step 2 — Confirm the symptom
```bash
kubectl --context kind-k8s17 get pods -l app=web -o wide
```
Both replicas sit `Pending` with no `NODE` assigned, indefinitely.

## Step 3 — Read the node's taint and the pod's rejection side by side
```bash
kubectl --context kind-k8s17 describe node k8s17-control-plane | grep -A1 Taints
```
```bash
kubectl --context kind-k8s17 describe pod -l app=web | grep -A10 Events
```
The node's `Taints:` line shows `dedicated=gpu-workloads:NoSchedule`. The
pod's Events show something like `0/1 nodes are available: 1 node(s) had
untolerated taint {dedicated: gpu-workloads}: NoSchedule.` — the
scheduler is telling you, in plain text, exactly which taint blocked it
and on which node. (Exact wording can vary slightly by Kubernetes
version; the taint key/value/effect it names will always match what
`describe node` shows.)

## Step 4 — Confirm the pod genuinely has no toleration for it
```bash
kubectl --context kind-k8s17 get deployment web -o jsonpath='{.spec.template.spec.tolerations}{"\n"}'
```
This prints nothing (or `null`) — there's no `tolerations` field on the
pod spec at all, so every taint on every node blocks it by default.

## Step 5 — Fix it two different ways (pick one, understand both)
**Option A — add a toleration** (workload-specific, node stays reserved
for anything else that also tolerates it):
```bash
kubectl --context kind-k8s17 patch deployment web --type=json -p '[
  {"op": "add", "path": "/spec/template/spec/tolerations", "value": [
    {"key": "dedicated", "operator": "Equal", "value": "gpu-workloads", "effect": "NoSchedule"}
  ]}
]'
```
**Option B — remove the taint** (opens the node to everything, loses
whatever reservation the taint was protecting):
```bash
kubectl --context kind-k8s17 taint nodes k8s17-control-plane dedicated=gpu-workloads:NoSchedule-
```
Either one unblocks scheduling — verify with:
```bash
kubectl --context kind-k8s17 get pods -l app=web -o wide
```
Think about which one you'd actually pick in a real cluster where the
taint exists for a real reason versus one where it was left over from a
retired workload.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a toleration that looks right but doesn't match:**
```bash
kubectl --context kind-k8s17 taint nodes k8s17-control-plane dedicated=gpu-workloads:NoSchedule --overwrite
kubectl --context kind-k8s17 patch deployment web --type=json -p '[
  {"op": "replace", "path": "/spec/template/spec/tolerations", "value": [
    {"key": "dedicated", "operator": "Equal", "value": "gpu-workloads", "effect": "PreferNoSchedule"}
  ]}
]'
kubectl --context kind-k8s17 get pods -l app=web -o wide
```
Pods are still `Pending`. Compare the toleration's `effect` field to the
taint's actual effect from `describe node` character by character — a
toleration has to match `key`, `value` (or use `operator: Exists` to
skip the value check), *and* `effect` exactly, or it doesn't apply at
all. Fix it so all three actually match.

**Challenge B — `NoExecute` on a node with pods already Running:**
```bash
kubectl --context kind-k8s17 taint nodes k8s17-control-plane dedicated=gpu-workloads:NoSchedule- --ignore-not-found 2>/dev/null || true
kubectl --context kind-k8s17 patch deployment web --type=json -p '[{"op":"remove","path":"/spec/template/spec/tolerations"}]' 2>/dev/null || true
kubectl --context kind-k8s17 rollout status deployment/web --timeout=60s
kubectl --context kind-k8s17 taint nodes k8s17-control-plane hardware=degraded:NoExecute
kubectl --context kind-k8s17 get pods -l app=web -w
```
This time the pods were already `Running` when the taint landed. Watch
what happens to them versus what happened in Steps 2-3. `NoSchedule`
only blocks *new* scheduling decisions; `NoExecute` actively evicts pods
already running on the node that don't tolerate it. Fix it, and while
you're at it check what `tolerationSeconds` would let you express that a
flat toleration can't: a pod that's willing to tolerate a `NoExecute`
taint *temporarily* before being evicted, instead of indefinitely.

See `solution.md` only after you've formed your own diagnosis.
