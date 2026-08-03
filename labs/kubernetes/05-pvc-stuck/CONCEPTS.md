# Lab 5 — Concept: Binding Is a Matching Problem, Not a Provisioning Guarantee

## What's actually going on

A `PersistentVolumeClaim` doesn't request storage directly — it requests
a *match*: a `PersistentVolume` (existing or dynamically created) whose
access mode, size, and `StorageClass` all satisfy what the claim asked
for. The PV controller (part of `kube-controller-manager`) continuously
watches unbound PVCs and available PVs looking for a satisfying pair.
When a PVC's `storageClassName` references a dynamic-provisioning
`StorageClass` (one with a real `provisioner` field, like kind's default
`standard` backed by `rancher.io/local-path`), a new PV gets created on
demand to match. But when the `storageClassName` doesn't exist at all, or
refers to a `StorageClass` with no provisioner (a purely static one, used
for hand-created PVs like hostPath or NFS mounts an admin provisioned in
advance), there is nothing that can conjure a new volume — the PVC can
only ever bind to a PV that already exists and already satisfies every
constraint. Both failure modes produce the exact same visible symptom
(`STATUS: Pending`, forever, no error thrown anywhere) because "no match
exists yet" and "no match will ever exist" are indistinguishable from the
claim object's status alone — the actual reason only shows up in
`kubectl describe pvc`'s Events, which is why that command, not
`kubectl get pvc`, is the real first diagnostic step every time.

`persistentVolumeReclaimPolicy` governs what happens to the underlying
storage *and the PV object* once its claim goes away, and `Retain` (as
opposed to the dynamically-provisioned default of `Delete`) is a
deliberate, conservative choice: don't destroy potentially-important data
just because the claim referencing it got deleted. But "don't destroy
the data" and "make the volume available for reuse" are different
promises, and Kubernetes only keeps the first one automatically. A
`Retain`-policy PV whose claim is deleted moves to `Released`, keeping
its `claimRef` populated with the old (now-nonexistent) claim's
name/UID — and the binding logic treats a `Released` PV as fundamentally
different from an `Available` one, refusing to hand it to any new claim
until an administrator explicitly clears that stale `claimRef`. This is
intentional friction: automatically rebinding a `Released` volume to some
unrelated new claim would mean a completely different workload silently
inheriting whatever data (secrets, database files, application state)
the previous claim's owner left behind.

Even once a PV is genuinely `Available`, binding still requires an exact
enough match on every dimension — access mode, `StorageClass` name, and
crucially **capacity greater than or equal to the request** (Kubernetes
picks the smallest PV that still qualifies, when multiple candidates
exist, but a PV smaller than the request never qualifies at all,
regardless of how well everything else matches). Static provisioning
gives you none of dynamic provisioning's "just make one that fits" safety
net — a capacity mismatch here is a dead end exactly like a
`storageClassName` typo, both surfacing as the same permanent `Pending`
state and both requiring the same discipline of reading `describe pvc`'s
actual event text instead of assuming the StorageClass name alone tells
the whole story.

## Where this shows up in the real world

Missing/misspelled `storageClassName` values are a routine
copy-paste-across-environments mistake — a Helm chart's default
`storageClassName` referencing a class that exists in the cluster it was
written for but not the one it's being deployed to (cloud-provider-named
classes like `gp2`/`gp3`/`premium-rwo` are especially prone to this across
different clusters/providers). `Released` PVs blocking reuse show up
constantly in stateful workload migrations and namespace teardown/rebuild
cycles — anyone using `Retain` for legitimate data-safety reasons (most
production databases-on-Kubernetes setups do) needs to know that
recreating a claim after deleting the old one is not a "just reapply the
YAML" operation; someone has to explicitly decide whether to reuse the
old PV (clearing `claimRef`) or provision a fresh one.

## Go deeper

- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/concepts/storage/persistent-volumes/ — the authoritative reference for the PV/PVC binding lifecycle, reclaim policies, and static vs. dynamic provisioning.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/concepts/storage/storage-classes/ — how `StorageClass`, provisioners, and binding modes fit together.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/debug/ — general troubleshooting task index this lab's diagnostic sequence follows.
- **Book:** *Kubernetes Patterns* — Bilgin Ibryam & Roland Huß — covers storage-related patterns including the operational realities of PV/PVC lifecycle management.
- **YouTube:** That DevOps Guy (Marcel Dempers) — https://www.youtube.com/@MarcelDempers — hands-on Kubernetes storage/PV troubleshooting videos.
