# Lab 6 — Concept: Eviction Is Kubelet Choosing a Victim Before the Kernel Has To

## What's actually going on

Every node's kubelet continuously monitors a handful of resource signals
— `memory.available`, `nodefs.available`, `nodefs.inodesFree`,
`imagefs.available`, `pid.available` — against configurable eviction
thresholds (soft and hard; the hard defaults are roughly
`memory.available<100Mi` and `nodefs.available<10%` in most
distributions). When a hard threshold is crossed, kubelet sets the
corresponding node Condition (`MemoryPressure`, `DiskPressure`,
`PIDPressure`) to `True` immediately and starts evicting pods to relieve
the pressure — proactively, before the resource is fully exhausted and
before the kernel's own OOM-killer would have to step in and kill a
process with no knowledge of which one is "safe" to lose. This is the
core reason eviction exists as a kubelet feature at all: the kernel OOM
killer picks victims based on its own heuristics (`oom_score_adj`,
memory usage) with zero awareness of Kubernetes concepts like "this is a
stateless canary" versus "this is a database" — kubelet's eviction
manager is deliberately trying to make a better-informed choice first.

That choice is made in a strict two-level order: **QoS class first,
resource usage second**. Every pod gets one of three QoS classes derived
entirely from its containers' `resources.requests`/`limits`:
`BestEffort` (no requests or limits set on anything), `Burstable` (some
requests set, but not equal to limits on every resource), or
`Guaranteed` (requests exactly equal limits on every container, every
resource). Eviction always exhausts every `BestEffort` candidate before
touching a single `Burstable` pod, and every `Burstable` candidate before
touching any `Guaranteed` pod — only within the same QoS tier does actual
usage of the pressured resource become the tiebreaker. This is why a
Burstable pod with a modest 64Mi memory request can survive eviction
pressure that kills a BestEffort pod using far less memory in absolute
terms: QoS class isn't a hint about priority, it's the first and
dominant sorting key, and setting even a small `resources.requests` value
is enough to leave the always-evicted-first tier entirely.

`MemoryPressure` and `DiskPressure` are independent Conditions driven by
independent underlying signals, but they trigger the identical eviction
mechanism once crossed — which is exactly why this lab's main scenario
(memory) and Challenge B (disk) feel structurally the same from the
`kubectl` side even though the root cause and the command you'd check
first (`free`/`/proc/meminfo` vs. `df`) are completely different. The
one command that disambiguates them immediately, before you go chasing
the wrong resource, is `kubectl describe node`'s Conditions section —
it's the single source of truth for which specific pressure kubelet is
actually reacting to, independent of what you might assume from a pod
just having disappeared.

## Where this shows up in the real world

Nodes running mixed workloads with inconsistent resource
requests/limits hygiene are a constant source of "why did my pod
disappear" incidents — teams that treat `resources.requests` as optional
boilerplate discover, usually during exactly the kind of incident this
lab simulates, that "no requests set" doesn't mean "no consequences," it
means "first in line to be evicted the moment any other workload on the
same node gets greedy." Real production node-pressure incidents are
often *caused* by exactly the same class of pod that's most vulnerable to
being evicted by it — a memory leak in an unmonitored batch job with no
limits set can push a shared node into `MemoryPressure`, at which point
kubelet evicts whatever else on that node also happens to have no
requests set, which is frequently unrelated, innocent workloads paying
for someone else's missing resource limits.

## Go deeper

- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/ — the authoritative reference for eviction signals, thresholds, and the QoS-based eviction order.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/ — how QoS class is actually derived from requests/limits.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/debug/ — general troubleshooting task index this lab's diagnostic sequence follows.
- **Book:** *Kubernetes in Action* — Marko Lukša — covers resource requests/limits, QoS classes, and eviction behavior in depth.
- **YouTube:** That DevOps Guy (Marcel Dempers) — https://www.youtube.com/@MarcelDempers — hands-on Kubernetes resource management and eviction videos.
