# Lab 13 — StatefulSet PVC Mismatch (Scale-Down Doesn't Mean Clean Slate)

## Objective
Scale a `StatefulSet` down and back up, and discover that the pod that
comes back doesn't get a fresh volume — it reattaches to the exact PVC
(and data) its old ordinal had before, because `StatefulSet`s do not
delete PVCs on scale-down by default. Learn to read `kubectl get pvc`
and `persistentVolumeClaimRetentionPolicy` instead of assuming scaling
down and back up is equivalent to a restart.

## Why this matters
Scaling a Deployment down and back up gives you fresh Pods with no
memory of what came before — that's the mental model most engineers
carry into `StatefulSet`s too, and it's wrong. Every ordinal in a
`StatefulSet` (`myapp-0`, `myapp-1`, ...) gets its own PVC from
`volumeClaimTemplates`, named `<volumeClaimTemplate
name>-<statefulset>-<ordinal>`, and that PVC's lifecycle is deliberately
decoupled from the Pod's — it survives Pod deletion, Pod rescheduling, and
scale-down, by design, because that persistence is the entire point of a
`StatefulSet` in the first place (a database replica that lost its data
every time it restarted would be useless). The surprise is what happens
on scale-*up*: a new Pod for an ordinal that already has an existing PVC
doesn't get a fresh volume, it reattaches to whatever's already there —
which is exactly right for "the node rebooted, give my replica its data
back," and exactly wrong for "I scaled down for a while, I expected a
clean member." Not knowing which one you're going to get is how stale
data quietly reappears in a "new" replica.

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
kind create cluster --name k8s13
```
(kind ships a default `standard` StorageClass backed by
`local-path-provisioner`, which is what lets `volumeClaimTemplates`
dynamically provision here with no extra setup.)

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates the `k8s13` kind cluster, then deploys a `StatefulSet`
called `myapp` with 3 replicas and a headless Service. Each Pod's
container, on startup, writes a `created-at` timestamp file into its
volume **only if one doesn't already exist**, and always appends a line
to a `boot-log.txt` — so you can later prove whether a Pod's volume is
brand new or has history.

## Step 2 — Confirm the baseline
```bash
kubectl --context kind-k8s13 get pods -l app=myapp
kubectl --context kind-k8s13 get pvc
kubectl --context kind-k8s13 exec myapp-1 -- cat /data/created-at
```
Three Pods (`myapp-0/1/2`), three Bound PVCs
(`data-myapp-0/1/2`), and `myapp-1`'s `created-at` shows the timestamp
from when it first started.

## Step 3 — Scale down
```bash
kubectl --context kind-k8s13 scale statefulset myapp --replicas=1
kubectl --context kind-k8s13 get pods -l app=myapp
kubectl --context kind-k8s13 get pvc
```
Pods `myapp-1` and `myapp-2` terminate — but their PVCs,
`data-myapp-1` and `data-myapp-2`, are still there, still `Bound`. Nothing
deleted them; nothing was ever asked to.

## Step 4 — Scale back up and check the data
```bash
kubectl --context kind-k8s13 scale statefulset myapp --replicas=3
kubectl --context kind-k8s13 wait --for=condition=Ready pod/myapp-1 --timeout=60s
kubectl --context kind-k8s13 exec myapp-1 -- cat /data/created-at
kubectl --context kind-k8s13 exec myapp-1 -- cat /data/boot-log.txt
```
`created-at` shows the **original** timestamp from Step 2, not a new one
— `myapp-1` reattached to `data-myapp-1`, its old volume, with its old
data still on it. `boot-log.txt` has multiple lines: one from the pod's
first ever start, and a new one from just now — proof this is the same
volume across the whole scale-down/scale-up cycle, not a fresh one.

## Step 5 — Get an actually-fresh volume, on purpose
If a genuinely clean slate is what you wanted, the PVC has to be deleted
explicitly — the `StatefulSet` will never do it for you under the default
retention behavior:
```bash
kubectl --context kind-k8s13 scale statefulset myapp --replicas=1
kubectl --context kind-k8s13 delete pvc data-myapp-1 data-myapp-2
kubectl --context kind-k8s13 scale statefulset myapp --replicas=3
kubectl --context kind-k8s13 wait --for=condition=Ready pod/myapp-1 --timeout=60s
kubectl --context kind-k8s13 exec myapp-1 -- cat /data/created-at
```
This time `created-at` shows a **new** timestamp — a fresh PVC got
provisioned for ordinal 1 because the old one was gone, and the
container's startup script created the file for the first time.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — `persistentVolumeClaimRetentionPolicy` doesn't mean what it sounds like:**
```bash
bash -c '
CTX=kind-k8s13
kubectl --context $CTX patch statefulset myapp --type=json -p="[
  {\"op\":\"add\",\"path\":\"/spec/persistentVolumeClaimRetentionPolicy\",\"value\":{\"whenScaled\":\"Delete\",\"whenDeleted\":\"Retain\"}}
]"
kubectl --context $CTX scale statefulset myapp --replicas=1
sleep 5
kubectl --context $CTX get pvc
kubectl --context $CTX delete statefulset myapp
sleep 5
kubectl --context $CTX get pvc
'
```
Scaling down this time actually deletes the departing ordinals' PVCs (as
`whenScaled: Delete` promises) — but deleting the entire `StatefulSet`
right after leaves the *remaining* PVC untouched, even though it looks
like "the StatefulSet is gone, surely everything related to it is gone
too." Explain why these two operations produce different outcomes even
though `Delete` appears once in the policy, and what `whenDeleted`
actually governs versus `whenScaled`.

**Challenge B — deleting a PVC that's still in use gets stuck, not deleted:**
```bash
bash -c '
CTX=kind-k8s13
kubectl --context $CTX get pods -l app=myapp
kubectl --context $CTX delete pvc data-myapp-0 --timeout=15s &
DELETE_PID=$!
sleep 3
kubectl --context $CTX get pvc data-myapp-0
kill $DELETE_PID 2>/dev/null || true
'
```
`myapp-0` is still Running and still using `data-myapp-0` the whole time.
The `delete` command doesn't fail outright, but the PVC doesn't disappear
either — check its `STATUS` column and, with `kubectl describe pvc
data-myapp-0`, find the specific field that's holding it open. Figure out
what actually has to happen before this delete can complete, and why
Kubernetes won't just rip the volume out from under a Pod that's actively
using it.

See `solution.md` only after you've formed your own diagnosis.
