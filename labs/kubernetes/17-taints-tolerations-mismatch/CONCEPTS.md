# Lab 17 — Concept: Taints Are a Node's Opt-Out, Tolerations Are a Pod's Opt-In

## What's actually going on

Every other scheduling mechanism in Kubernetes — node selectors, node
affinity — works by the pod actively asking for a node with certain
properties. Taints work backwards: a node carries a taint that says "by
default, nothing gets scheduled here," and it's up to individual pods to
declare, via a matching toleration, that they're specifically okay with
that taint. This inversion is the whole point — it lets you reserve a
node (or a whole pool of nodes) for a narrow purpose without having to
go add exclusion rules to every *other* workload in the cluster; the
default is exclusion, and only the workloads that explicitly tolerate it
get in. The scheduler checks this as a hard predicate during scheduling:
if a node has any taint the pod doesn't tolerate, that node is removed
from the candidate list entirely, silently, before any other scoring
happens — no error is raised, the pod just never gets that node as an
option, which is why `Pending` from an untolerated taint looks
identical, from the pod's own status, to `Pending` from any other
scheduling constraint. The only place the specific reason shows up is
the `FailedScheduling` event in `kubectl describe pod`, which names the
exact taint that blocked it.

A toleration is not "immune to all taints" or even "immune to this
taint's key" — it has to match a specific combination of `key`,
`value` (or use `operator: Exists`, which matches any value for that
key), and `effect`. That last field, `effect`, is where the real
distinction between the three taint effects lives:
- `NoSchedule` — hard block on new scheduling. Pods already running on
  the node are left alone.
- `PreferNoSchedule` — a soft version: the scheduler tries to avoid the
  node but will still use it if nothing else is a viable candidate.
- `NoExecute` — blocks new scheduling *and* actively evicts any
  already-running pod that doesn't tolerate it, essentially immediately
  (or after `tolerationSeconds` if the pod's toleration specifies one).
  This is the only one of the three that reaches backwards in time to
  pods that were already there before the taint was applied.

Because these are matched as a strict tuple, a toleration that gets even
one field wrong — the most common being effect (tolerating
`PreferNoSchedule` when the actual taint is `NoSchedule`, as reproduced
in Challenge A) — is functionally the same as having no toleration at
all. Kubernetes doesn't do partial credit here.

## Where this shows up in the real world

Node pools reserved for GPU workloads, high-memory workloads, or
compliance-isolated workloads are almost always built with a taint on
the node pool plus a matching toleration baked into that workload's
Helm chart or deployment template — and the classic failure is a new,
unrelated Deployment accidentally landing in that node pool's
autoscaling group (or a taint that was supposed to be cluster-wide only
getting applied to some nodes), leaving pods permanently `Pending` with
no obvious cause in the Deployment's own YAML. `NoExecute` taints show
up constantly in a slightly different guise: Kubernetes itself
automatically applies built-in `NoExecute` taints like
`node.kubernetes.io/not-ready` and `node.kubernetes.io/unreachable` when
a node's health degrades, which is exactly how pods get proactively
evicted off a failing node before you'd otherwise notice — the same
mechanism this lab reproduces manually with `hardware=degraded`, just
triggered by kubelet/the node controller instead of a human.

## Go deeper

- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/ — the authoritative reference on taint effects, toleration matching rules, and `tolerationSeconds`.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/concepts/scheduling-eviction/ — the broader scheduling/eviction concept index, including how taints interact with other scheduling mechanisms.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/debug/ — general troubleshooting task index this lab's diagnostic sequence follows.
- **Book:** *Kubernetes in Action* — Marko Lukša — covers taints/tolerations alongside node affinity in the scheduling chapter.
- **Book:** *Kubernetes Patterns* — Bilgin Ibryam & Roland Huß (O'Reilly) — scheduling patterns that use taints for workload isolation.
- **YouTube:** CNCF — https://www.youtube.com/@cloudnativefdn — conference talks covering scheduler internals and taint-based node isolation strategies.
