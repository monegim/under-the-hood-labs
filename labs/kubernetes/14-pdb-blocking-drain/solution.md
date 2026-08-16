# Lab 14 — Solutions

## Challenge A — `maxUnavailable: 0` blocks drain regardless of replica count

**Check:**
```bash
kubectl --context kind-k8s14 get pdb checkout-pdb-strict
kubectl --context kind-k8s14 describe pdb checkout-pdb-strict
```
`ALLOWED DISRUPTIONS` is `0` even with 3/3 Pods healthy. `describe` shows
`Max unavailable: 0`.

**Diagnosis:** `minAvailable` and `maxUnavailable` are two ways of
expressing the same underlying constraint, but they don't scale the same
way as replica count changes. `minAvailable: 1` on a 1-replica Deployment
happens to produce `ALLOWED DISRUPTIONS: 0` because 1 healthy minus a
`minAvailable` of 1 leaves no room — but that headroom grows automatically
as replicas grow (2 replicas gives you 1 disruption of headroom, 3 gives
you 2, and so on). `maxUnavailable: 0` is a flat, absolute statement
completely independent of replica count: "at no point may any Pod covered
by this selector be unavailable due to a *voluntary* disruption," full
stop, whether there are 1 or 100 replicas. It's a legitimate, intentional
configuration — teams sometimes use it for workloads where even one
missing replica has real user-facing impact and they'd rather block
maintenance entirely than allow it. It's just easy to mistake for a bug
because "we have 3 replicas, we can definitely spare one" is a completely
reasonable assumption that this specific policy overrides on purpose.

**Fix:** there's no "wrong config" to fix here — the fix is a decision,
not a patch. Either the team genuinely wants zero voluntary disruptions
ever (in which case node maintenance on this workload has to happen some
other way — e.g. draining a *different* node the Pod isn't on, or scaling
onto new nodes and letting old ones empty naturally), or the policy is
stricter than intended and should be relaxed:
```bash
kubectl --context kind-k8s14 patch pdb checkout-pdb-strict --type=json -p='[
  {"op":"replace","path":"/spec/maxUnavailable","value":1}
]'
kubectl --context kind-k8s14 drain k8s14-worker --ignore-daemonsets --delete-emptydir-data --timeout=30s
```

**Lesson:** `ALLOWED DISRUPTIONS: 0` means the same thing regardless of
which field produced it — read the PDB's actual `spec` (`minAvailable`
vs. `maxUnavailable`) before assuming "we have plenty of replicas" is
relevant. `maxUnavailable: 0` is a valid, sometimes deliberate way to say
"never, regardless of headroom."

---

## Challenge B — an unmanaged Pod blocks drain, no PDB involved at all

**Check:**
```bash
kubectl --context kind-k8s14 get pdb
kubectl --context kind-k8s14 get pod standalone-debug -o yaml | grep -A3 ownerReferences
```
`get pdb` returns no resources — there is genuinely no
`PodDisruptionBudget` anywhere. `get pod ... -o yaml` shows
`standalone-debug` has no `ownerReferences` at all (or the field is
simply absent) — it wasn't created by a Deployment, ReplicaSet,
StatefulSet, DaemonSet, or Job; it's a bare Pod someone `kubectl run` on
its own.

**Diagnosis:** `kubectl drain` refuses, by default, to evict Pods that
aren't managed by a controller. The reasoning is separate from PDBs
entirely: if a controller owns a Pod, deleting it is safe because the
controller will simply recreate it elsewhere — that's the whole point of
drain, moving workloads off a node without losing them. A bare Pod with
no controller has no such guarantee: delete it, and it is simply gone,
permanently, with nothing watching to bring it back. `drain`'s default
behavior treats that as too risky to do silently, and refuses with an
error naming "Pods declare no controller" rather than anything about
disruption budgets.

**Fix (only if data loss on that Pod is genuinely acceptable):**
```bash
kubectl --context kind-k8s14 drain k8s14-worker --ignore-daemonsets --delete-emptydir-data --force --timeout=30s
```
`--force` is what tells `kubectl drain` "yes, I understand this Pod has
no controller and won't come back — delete it anyway." It should be a
deliberate, informed choice every time, not a default reflex for
unblocking a stuck drain.

**Lesson:** a stuck/refused drain has (at least) two structurally
different causes that require reading the *specific* error text to
distinguish — a `PodDisruptionBudget` violation (Challenge A, Steps 3-5)
and an unmanaged/bare Pod (this challenge) — and they call for opposite
kinds of fixes: the PDB case wants you to create headroom (scale up,
relax the policy) before proceeding; the bare-Pod case wants you to make
an explicit, informed decision about whether losing that specific Pod for
good is acceptable, via `--force`. Neither should be reached for
reflexively just because "drain isn't working."
