# Lab 5 — Solutions

## Challenge A — Released PV blocked from reuse by claimRef

**Check:**
```bash
kubectl --context kind-k8s05 get pv manual-pv
kubectl --context kind-k8s05 get pv manual-pv -o yaml | grep -A4 claimRef
kubectl --context kind-k8s05 describe pvc manual-pvc-2
```
`get pv` shows `manual-pv` in `STATUS: Released`, not `Available`. The
`claimRef` block still references the original `manual-pvc` by name and
UID — a claim that no longer exists. `describe pvc manual-pvc-2` shows
it's simply unbound, waiting for a volume, exactly like the main lab's
symptom but for a different underlying reason.

**Diagnosis:** with `persistentVolumeReclaimPolicy: Retain`, deleting the
PVC does **not** delete or reset the underlying PV or its data — that's
the entire point of `Retain` (protect the data from an accidental `kubectl
delete pvc`). But the PV transitions to `Released`, not back to
`Available`, and it keeps its `claimRef` pointing at the now-deleted
claim. A `Released` PV is not eligible for automatic binding to any new
PVC, even one requesting the exact same size/access-mode/StorageClass —
Kubernetes requires an explicit administrator action (clearing
`claimRef`) before that capacity can be handed to anyone else, precisely
so a new, unrelated claim can never accidentally attach to a volume that
might still contain another team's old data.

**Fix:**
```bash
kubectl --context kind-k8s05 patch pv manual-pv --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'
kubectl --context kind-k8s05 get pv manual-pv
kubectl --context kind-k8s05 get pvc manual-pvc-2
```
(`get pv` should now show `Available`, and `manual-pvc-2` should bind
shortly after — no need to delete/recreate the PVC.)

**Lesson:** `Retain` means "never silently delete my data," not "make this
volume available again automatically" — those are two different
guarantees, and conflating them is exactly how a `Released` PV ends up
blocking a legitimate new claim indefinitely. Always check `kubectl get
pv -o yaml | grep -A4 claimRef` before assuming "a PV of the right size
exists" is enough for a bind to happen.

---

## Challenge B — capacity too small, no PV can satisfy the claim

**Check:**
```bash
kubectl --context kind-k8s05 get pv
kubectl --context kind-k8s05 describe pvc big-pvc
```
`get pv` shows `small-pv` at `500Mi` capacity, `Available`, same
`storageClassName: manual` as `big-pvc`. `describe pvc big-pvc`'s Events
show something like `no persistent volumes available for this claim and
no storage class is set` (for statically-provisioned StorageClasses with
no dynamic provisioner backing them, Kubernetes can only bind to an
existing PV, never create a new one on demand).

**Diagnosis:** for static provisioning (a `StorageClass` name with no
actual provisioner behind it, or a raw PV/PVC pair with no StorageClass
at all), Kubernetes' PV controller binds a PVC to the *smallest PV that
still satisfies every one of the claim's requirements* — access mode,
StorageClass, and **capacity greater than or equal to the request**.
`small-pv` at 500Mi cannot satisfy a 5Gi request no matter how identical
everything else about it is; there is no provisioner here that can create
a bigger volume on demand, so the claim just sits `Pending` forever,
identical in symptom to a missing-StorageClass problem even though the
StorageClass itself is fine.

**Fix:** either request a size the existing PV can satisfy, or create a
PV that's actually big enough:
```bash
cat <<EOF | kubectl --context kind-k8s05 apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: big-pv
spec:
  capacity:
    storage: 5Gi
  accessModes: ["ReadWriteOnce"]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /tmp/lab5-big-pv
EOF
kubectl --context kind-k8s05 get pvc big-pvc
```

**Lesson:** "a PV with the right StorageClass exists" and "a PV that can
actually satisfy this claim exists" are different checks — always compare
`kubectl get pv`'s `CAPACITY` column against the PVC's requested size
directly, not just the StorageClass name, especially with statically
provisioned storage where there's no dynamic provisioner to fall back on
when nothing matches.
