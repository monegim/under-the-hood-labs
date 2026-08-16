# Lab 13 — Solutions

## Challenge A — `whenScaled` and `whenDeleted` are independent axes

**Check:**
```bash
kubectl --context kind-k8s13 get statefulset myapp -o jsonpath='{.spec.persistentVolumeClaimRetentionPolicy}{"\n"}'
kubectl --context kind-k8s13 get pvc
```
After scaling down with `whenScaled: Delete`, `data-myapp-1` and
`data-myapp-2` are actually gone — that half worked as expected. After
then deleting the whole `StatefulSet`, `data-myapp-0` is still sitting
there, `Bound`, completely unaffected.

**Diagnosis:** `persistentVolumeClaimRetentionPolicy` has two separate
fields because it's answering two separate questions, and this lab set
them to different values on purpose: `whenScaled` governs what happens to
an ordinal's PVC when that ordinal is removed by *reducing
`spec.replicas`* — set to `Delete`, it cleans up as replicas shrink.
`whenDeleted` governs what happens to *every remaining* PVC when the
`StatefulSet` object itself is deleted (or the whole set is scaled to
zero via deletion) — this lab left it at `Retain`, the default, so the
last surviving PVC is intentionally left behind for whoever might want to
recreate the `StatefulSet` and reattach to it later. Nothing here is a
bug: the two knobs exist precisely so "shrinking the fleet" and "tearing
the whole thing down" can have different data-safety defaults, since
they're very different operational events.

**Fix (if you actually wanted the last PVC gone too):**
```bash
kubectl --context kind-k8s13 delete pvc data-myapp-0
```
Or, before deleting the `StatefulSet`, set `whenDeleted: Delete` as well
if that's genuinely the intended behavior going forward.

**Lesson:** don't read `persistentVolumeClaimRetentionPolicy: {whenScaled:
Delete}` as "this StatefulSet deletes its PVCs" — it only deletes the
PVCs for ordinals that go away via scale-down. Full deletion of the
`StatefulSet` is governed by a completely separate field
(`whenDeleted`), defaulting to `Retain` unless you explicitly opt out,
specifically so destroying the controller object doesn't implicitly
destroy your data too.

---

## Challenge B — a PVC in active use won't finish deleting

**Check:**
```bash
kubectl --context kind-k8s13 get pvc data-myapp-0
kubectl --context kind-k8s13 describe pvc data-myapp-0
```
`get pvc` shows `STATUS: Terminating` — not gone, not an error, just
stuck there. `describe pvc`'s output includes a `Finalizers` entry:
`kubernetes.io/pvc-protection`.

**Diagnosis:** every PVC that's currently mounted by a running Pod
carries the `kubernetes.io/pvc-protection` finalizer, which the API
server will not let a delete complete past while any Pod still
references that PVC. `kubectl delete pvc` does mark the object for
deletion (that's why `get pvc` shows `Terminating` rather than the
command erroring outright) — but the object physically stays in etcd,
finalizer intact, until whatever's consuming it stops. This exists
specifically to prevent exactly the accident this challenge sets up:
deleting a volume out from under an actively-writing Pod, which would
otherwise silently corrupt or lose in-flight data with no warning.

**Fix:**
```bash
kubectl --context kind-k8s13 delete pod myapp-0
kubectl --context kind-k8s13 get pvc data-myapp-0
```
Once the Pod using it is gone, the finalizer is removed and the
`Terminating` PVC actually finishes deleting (or, if the `StatefulSet`
immediately recreates `myapp-0`, the new Pod will just reattach to
whatever PVC exists at that moment — check `kubectl get pvc` again to see
which outcome you got, since both are possible depending on timing).

**Lesson:** `kubectl get pvc` showing `Terminating` for longer than
expected isn't a stuck/broken cluster — it's `pvc-protection` doing its
job. The fix is never to force through the finalizer; it's to remove
whatever's actually using the volume first (or understand you're
choosing a data-loss window if you truly intend to detach it while in
use).
