# Lab 20 — Solutions

## Challenge A — same symptom, spec looks fine, completely different reason

**Check:**
```bash
kubectl --context kind-k8s20 describe pod -l app=webapp | grep -A3 "Events:"
```
```
Warning  FailedScheduling  ...  0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector. ...
```
Note this is a completely different message from Step 3's
`Insufficient cpu` — even though the CPU request was also lowered to
`200m` (well within what the node offers) as part of this same patch.

**Diagnosis:** `nodeSelector: {disktype: ssd}` tells the scheduler
"only ever consider nodes carrying the label `disktype=ssd`." Checking
the node's actual labels:
```bash
kubectl --context kind-k8s20 get nodes --show-labels
```
shows no `disktype` label anywhere — a plain `kind` node doesn't carry
disk-type labels by default; that label only exists on real clusters
where something (a cloud provider's node initializer, an admin, a
labeling controller) puts it there deliberately. The scheduler isn't
weighing "close enough" candidates and picking the best one — a
`nodeSelector` is a hard filter. Zero nodes carry the label, so zero
nodes are even considered, regardless of how small the Pod's resource
requests are. This is exactly why Step 4's fix (lowering `cpu`) did
nothing when applied here: it addresses a completely unrelated
dimension of "can this pod be placed."

**Fix:** either remove the `nodeSelector` (correct if it was added by
mistake, or copied from a manifest meant for a different, real
cluster), or add the matching label to a real candidate node if the
selector is intentional:
```bash
kubectl --context kind-k8s20 label node $(kubectl --context kind-k8s20 get nodes -o jsonpath='{.items[0].metadata.name}') disktype=ssd
```

**Lesson:** `Pending` plus `FailedScheduling` is not one failure mode,
it's an entire category — the scheduler tried, considered every node
it has, and rejected all of them, for a reason that's always spelled
out in the event message but never in the status column alone. Fixing
the wrong dimension (resources, when the actual blocker is a selector
— or the reverse) produces zero visible change and zero error telling
you that you fixed the wrong thing, which is exactly what makes this
category of incident slow to resolve under pressure: every fix attempt
looks equally plausible until you've actually read the message.

---

## Challenge B — the new Pod's own request is completely reasonable

**Check:**
```bash
kubectl --context kind-k8s20 describe pod -l app=webapp | grep -A3 "Events:"
```
```
Warning  FailedScheduling  ...  0/1 nodes are available: 1 Insufficient cpu. ...
```
Same wording as Step 3 — but `webapp` here only asks for `200m`, a
fifth of one core.

**Diagnosis:** the scheduler's `Insufficient cpu` check has nothing to
do with whether a Pod's own request is "reasonable" in isolation — it
compares the Pod's request against how much of the node's `Allocatable`
capacity is already claimed by *every other Pod's* requests, running or
not:
```bash
kubectl --context kind-k8s20 describe node $(kubectl --context kind-k8s20 get nodes -o jsonpath='{.items[0].metadata.name}') | sed -n '/Allocated resources:/,/Events:/p'
```
`baseline`'s 20 replicas already claim close to 100% of the node's CPU
before `webapp` is even applied — some of `baseline`'s own replicas
are `Pending` for the identical reason. `webapp`'s request isn't the
problem; there's simply no CPU left to give it, no matter how small a
number it asks for. Reading only `webapp`'s own resource block would
never reveal this — the manifest is completely correct on its own
terms, in complete isolation from everything else already running on
the cluster.

**Fix:** free up capacity elsewhere on the node — scale down or remove
some of `baseline`'s replicas:
```bash
kubectl --context kind-k8s20 scale deployment baseline --replicas=5
```
`webapp` schedules on its own the moment there's room, with no change
to its own spec at all.

**Lesson:** `kubectl describe <the Pod that's stuck>` only tells half
the story when the actual constraint is cluster-wide capacity, not
anything about that one Pod. `kubectl describe node`'s Allocated
Resources section — what's already claimed, by everything, whether or
not it's actually using what it claimed — is the check that actually
answers "is there room," and it's the one step easiest to skip when a
Pod's own manifest looks completely unremarkable and the instinct is
to keep staring at it instead of looking at what else is sharing the
node.
