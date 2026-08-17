# Lab 20 — Concept: How the Scheduler Decides "Fits" or "Doesn't"

## What's actually going on

Creating a Pod never puts it on a node directly — the API server just
records that the Pod exists, unscheduled, and the scheduler is a
completely separate control loop that watches for Pods with no node
assigned and tries to find one. For every unscheduled Pod, it runs
every node through a filtering pass (historically called "predicates"):
does this node have the resources this Pod's containers request left
over, after subtracting every other Pod's requests already assigned to
it (regardless of whether those Pods are actually using what they
asked for)? Does this node carry every label a `nodeSelector` or
required node affinity demands? Does this node have a taint the Pod
doesn't tolerate? Every one of these checks is independent, and a node
only becomes a candidate if it passes *all* of them — there's no
partial credit, no "close enough," no ranking a node higher for mostly
matching. A Pod that fails every node on any single check sits
`Pending` with a `FailedScheduling` event, and the scheduler keeps
retrying it indefinitely on its own schedule, forever, with nothing
that looks like "giving up" or escalating.

The two mechanisms this lab isolates both fail this filtering pass, but
for reasons that share almost nothing except the umbrella term
"can't schedule." A resource check compares a number (the Pod's
`requests.cpu`) against another number computed from live cluster
state (the node's `Allocatable.cpu` minus the sum of every other Pod's
`requests.cpu` already assigned there) — it's arithmetic, and it can
fail either because the Pod's own number is unreasonable in isolation
(the main lab: nothing else running, and the Pod alone asks for more
than the whole node has) or because the *other side* of the
subtraction already ate the budget (Challenge B: the Pod's own number
is completely ordinary, but everything else already scheduled there
left nothing over). A `nodeSelector`/affinity check, on the other hand,
is a label match, not arithmetic at all — a node either carries the
required label or it doesn't, and no amount of resource headroom
changes that answer. `kubectl describe pod`'s Events section reports
which specific check failed in its own wording every time
(`Insufficient cpu` vs. `didn't match Pod's node affinity/selector`),
which is the one place this distinction is actually visible —
`kubectl get pods` alone only ever shows the same undifferentiated
`Pending`.

## Where this shows up in the real world

Resource requests are usually written once, early, often copied from a
template or another service's manifest, and then never revisited as
either the workload's real needs or the target cluster's node sizes
change — a value that was completely reasonable on a fleet of large
production nodes can be larger than an entire staging or local
cluster's single node has to offer, and nothing about applying the
manifest warns you. The "someone else already claimed the capacity"
version of this (Challenge B) is the more common one in a shared,
long-running cluster specifically: teams request resources based on a
guess, rarely revisit them downward even after real usage turns out to
be much lower, and the scheduler has no way to know the difference
between a Pod that's genuinely using its full request and one that's
sitting nearly idle — it only ever looks at what was *requested*. A
cluster can look, and be, completely full from the scheduler's
perspective while `docker stats`/`kubectl top` shows most of that
capacity going unused, and the fix in that situation is capacity
planning and rightsizing existing workloads, not touching the new
Pod that happened to be the one that couldn't fit.

## Go deeper

- **Website/docs:** Kubernetes documentation, "Assigning Pods to Nodes" — https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/ — `nodeSelector`, node affinity, and how they differ from resource-based scheduling.
- **Website/docs:** Kubernetes documentation, "Manage Resources for Containers" — https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ — the authoritative explanation of `requests` vs. `limits` and exactly what the scheduler does with each.
- **Website/docs:** Kubernetes documentation, "Kubernetes Scheduler" — https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/ — the filtering-then-scoring model this lab's Challenges each isolate one half of.
- **Blog:** Learnk8s, "Understanding Kubernetes limits and requests" — https://learnk8s.io/kubernetes-instrumentation — practical framing of why an entire cluster can appear "full" from the scheduler's point of view while actual utilization is low.
- **Book:** *Kubernetes Up & Running* — Brendan Burns, Joe Beda, Kelsey Hightower (O'Reilly) — the scheduling and resource-management chapters cover exactly this class of "the manifest is valid, the cluster state is why it won't run" incident.
