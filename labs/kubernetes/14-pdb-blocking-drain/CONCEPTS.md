# Lab 14 — Concept: Drain Uses the Eviction API, and PDBs Are a Real Veto

## What's actually going on

`kubectl drain` is really two things chained together: it cordons the
node (marks it unschedulable, so nothing new lands there), then walks the
list of Pods currently on it and, for each one that isn't a DaemonSet Pod
(with `--ignore-daemonsets`), issues a request against that Pod's
**Eviction** subresource — not a plain `DELETE`. That distinction matters
enormously. A plain `kubectl delete pod` goes straight to deleting the
object; the API server doesn't consult any `PodDisruptionBudget` at all,
because a direct delete is treated as unconditional intent. An eviction
request, by contrast, is explicitly designed to be *refusable*: the API
server's eviction handler checks every `PodDisruptionBudget` whose
selector matches the Pod, computes whether granting the eviction would
drop the number of healthy, PDB-covered Pods below what the budget
allows, and if so, responds `429 Too Many Requests` — a deliberate,
documented "not right now," not an error. `kubectl drain` retries
evictions on that response for a while (respecting `--timeout`) and
eventually gives up and reports the drain as failed, which is exactly
what you see in Steps 3-4: not a crash, not a hang, a considered refusal
happening over and over.

A `PodDisruptionBudget`'s `status.disruptionsAllowed` field (what
`kubectl get pdb`'s `ALLOWED DISRUPTIONS` column shows) is the live
result of that computation: current healthy replicas matching the
selector, minus whatever `minAvailable` requires (or, for
`maxUnavailable`, current replicas minus how many are already
unavailable minus the `maxUnavailable` ceiling). Both spec fields express
the same underlying idea — "how many Pods can safely go away right now"
— but they don't behave identically as replica count changes:
`minAvailable`'s effective headroom scales up automatically as you add
replicas, while `maxUnavailable: 0` is an absolute ceiling that stays at
zero no matter how many replicas exist. This is why "we have 3 replicas,
surely one can go" is not a safe inference without actually reading which
field the PDB uses and what value it's set to.

The "no controller" refusal (Challenge B) is a completely separate check,
unrelated to PDBs: `kubectl drain` inspects each Pod's `ownerReferences`
and, by default, refuses to touch Pods that don't have one from a
recognized controller kind (ReplicaSet, StatefulSet, DaemonSet, Job,
etc.). The reasoning is about recoverability, not availability budgets —
a controller-owned Pod that gets evicted will be recreated somewhere else
automatically, so evicting it is safe by construction; a bare Pod with no
controller simply vanishes forever if deleted, so `drain` treats deleting
it as an irreversible action requiring an explicit `--force`, distinct
from (and orthogonal to) whatever any PDB says.

## Where this shows up in the real world

Node upgrades, node-pool replacements, and cluster-autoscaler scale-downs
all go through exactly this drain-and-evict path, and a PDB refusing an
eviction is one of the most common reasons a rolling node upgrade stalls
partway through — usually surfacing as "the upgrade job/controller has
been stuck for 20 minutes on one node" rather than an obvious error
anywhere. It's a legitimate signal worth investigating (is this workload
actually under-provisioned for safe maintenance?) rather than an
obstacle to route around, and the anti-pattern of reaching for
`--grace-period=0 --force` (a raw delete, bypassing eviction and the PDB
entirely) to "unstick" an automated drain is a real, repeated cause of
self-inflicted outages during otherwise routine maintenance.

## Go deeper

- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/run-application/configure-pdb/ — the authoritative reference for PDB semantics, `minAvailable` vs. `maxUnavailable`, and how `disruptionsAllowed` is computed.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/ — the official guide to draining nodes safely, including the Eviction API and PDB interaction.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/debug/ — general troubleshooting methodology, useful for reasoning about "is this refusal a bug or a safety mechanism."
- **Book:** *Kubernetes in Action* — Marko Lukša — covers voluntary vs. involuntary disruptions and PDB design in depth.
- **YouTube:** That DevOps Guy (Marcel Dempers) — https://www.youtube.com/@MarcelDempers — hands-on node drain and disruption budget videos.
