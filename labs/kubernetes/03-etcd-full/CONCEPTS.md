# Lab 3 — Concept: etcd's Backend Quota, MVCC History, and Why Compact Isn't Defrag

## What's actually going on

Every object in a Kubernetes cluster — every Pod, ConfigMap, Secret,
Deployment, everything `kubectl get` can show you — is a key in etcd, the
distributed key-value store the entire control plane is built on. etcd
stores its data in a single-file embedded database (bbolt, a B+tree
key-value store) on disk, and enforces a hard ceiling on that file's size
via `--quota-backend-bytes` (2GiB by default in most Kubernetes
distributions). This exists as a deliberate safety mechanism: without a
quota, a runaway workload — a controller that keeps writing without
cleaning up, a CI pipeline leaving thousands of completed Jobs around, a
leak of Secrets or Events — could grow etcd's database without bound
until it exhausts the underlying disk entirely, which risks corrupting
the one component every other Kubernetes component depends on. When the
backend size crosses the quota, etcd raises an **alarm** (`NOSPACE`)
cluster-wide and switches into a deliberately conservative mode: reads
keep working normally (the data that's already there is all still fully
readable), but every write is rejected outright with `etcdserver: mvcc:
database space exceeded`, until an operator explicitly clears the alarm.
This is why `kubectl get`/`describe` behave completely normally under
this failure while `kubectl create`/`apply`/`delete` all fail identically
— the alarm is a binary write-gate, not a performance degradation.

etcd is an MVCC (multi-version concurrency control) store: every write to
a key doesn't overwrite the old value in place, it creates a new
*revision* of that key while the old revision stays around (this is what
makes etcd's watch API and Kubernetes' resourceVersion-based optimistic
concurrency possible — clients can watch for changes since a specific
past revision). Left unchecked, this means the backend file grows
forever even if the *logical* amount of live data stays constant, purely
from accumulated history. `etcdctl compact <revision>` tells etcd it's
safe to discard all history strictly older than the given revision — but
compaction only marks that space as reusable free pages *inside* the
existing bbolt file; it does not shrink the file on disk, and correctly
does not, by itself, change what `endpoint status` reports as `DB SIZE`.
`etcdctl defrag` is the separate operation that actually rewrites the
backend file from scratch, keeping only live pages, which is what
physically shrinks the file and reduces the reported size. Compact
without defrag is a common half-fix mistake precisely because compact
returns success with no error — there's nothing that visibly tells you
it didn't finish the job.

Once a real production incident hits `NOSPACE`, the recovery sequence is
always the same three steps in order: delete/reduce the actual data
causing bloat first (no point compacting garbage you're about to
regenerate), `compact` to the current revision to mark old history
reclaimable, then `defrag` to physically shrink the file, and finally
`etcdctl alarm disarm` — which is the step that actually resumes writes;
compacting and defragging alone do not clear the alarm on their own. In a
real multi-member etcd cluster (unlike this lab's single-node kind
setup), defrag must be run one member at a time — a member briefly
blocks/pauses while defragmenting its own file, and defragmenting every
member simultaneously risks the cluster losing quorum mid-operation,
which is a much worse outage than the original quota alarm.

## Where this shows up in the real world

`etcdserver: mvcc: database space exceeded` is a real, well-documented
production incident class, usually triggered by exactly the workloads
this lab's opening paragraph describes: a controller or CI system that
creates far more objects (Secrets, ConfigMaps, completed Jobs, Events)
than it cleans up, silently growing etcd's backend over weeks or months
until it crosses the quota all at once. Because reads keep working the
entire time, the cluster often looks completely healthy in dashboards
right up until the first failed deployment or scale event, which is why
etcd's own `DB SIZE` and alarm state are worth monitoring proactively
(most production setups also enable `--auto-compaction-mode=periodic
--auto-compaction-retention=1h` specifically so compaction happens
continuously instead of being a manual, reactive step during an
incident).

## Go deeper

- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/ — the official guide to etcd operations in a Kubernetes cluster, including compaction and defragmentation.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/debug/ — general troubleshooting task index this lab's diagnostic sequence follows.
- **Website/docs:** etcd docs — https://etcd.io/docs/v3.5/op-guide/maintenance/ — the authoritative reference for `quota-backend-bytes`, compaction, defragmentation, and alarms (etcd's own maintenance guide, not a Kubernetes-specific rehash).
- **Website/blog:** Learnk8s blog — https://learnk8s.io/blog — has practical posts on Kubernetes control-plane internals and failure diagnosis.
- **YouTube:** CNCF — https://www.youtube.com/@cloudnativefdn — several KubeCon talks cover etcd operations and scaling etcd safely in production.
