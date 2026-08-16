# Lab 11 — Concept: ResourceQuota Is Enforced by Admission, Not by a Background Reconciler

## What's actually going on

A `ResourceQuota` isn't a monitor that watches usage and reacts after the
fact — it's enforced synchronously, inside the API server's admission
chain, on every single object-create request that touches a resource type
the quota covers. When you `kubectl apply` a Pod, the request passes
through authentication, then RBAC authorization, then a series of
admission plugins before it's ever written to etcd. `ResourceQuota` is one
of those plugins: it looks up every `ResourceQuota` object in the target
namespace, sums up what the new object would add to each covered resource,
and compares that against the `hard` limits. If the sum would exceed any
one of them, the entire request is rejected with `403 Forbidden` — the
Pod is never created, not created-then-deleted, not created-in-a-degraded
state. This is why the error surfaces immediately on the exact command
that crossed the line, and why it's a `Forbidden` status — the same HTTP
code RBAC denials use, which is precisely what makes it easy to
misdiagnose as a permissions problem if you don't read the message body.

Quota tracking itself is just a `status.used` field on the `ResourceQuota`
object, incremented and decremented as matching objects are created and
deleted — `kubectl describe resourcequota`'s `Used`/`Hard` table is
reading that status directly, not computing anything live. Crucially,
quota enforcement for compute resources (`requests.cpu`,
`limits.memory`, etc.) has a second, stricter behavior beyond "don't
exceed the hard cap": if a namespace has a quota covering a given compute
resource, every Pod created in that namespace *must* explicitly specify
that resource on every container, or the Pod is rejected outright — no
partial credit, no implicit zero. This existed specifically to prevent
Pods with no requests from being able to consume unbounded resources
while still nominally "fitting" inside a quota that only tracks explicit
values; a `LimitRange` object can set namespace-default requests/limits
so ordinary Pods don't have to specify this by hand.

The other easy-to-miss mechanic is *where* the rejection surfaces for
anything not created directly as a bare Pod. A Deployment update (like
`kubectl scale`) only ever touches the Deployment object's
`spec.replicas` — that succeeds unconditionally, quota or no quota. The
actual Pod-create calls that quota admission checks happen one level down,
inside the ReplicaSet controller's reconcile loop, asynchronously, well
after your `kubectl` command already returned. That's why a stalled
scale-up shows no error on the Deployment itself — you have to go look at
the ReplicaSet's Events to see the `FailedCreate` quota rejections the
controller is hitting on every retry.

## Where this shows up in the real world

Per-team or per-namespace `ResourceQuota`s are the default multi-tenancy
control on any shared cluster — without them, one namespace's runaway
Deployment or leaked batch Jobs can starve every other tenant of
schedulable capacity. The recurring incident is almost never "we need
more quota than we've ever needed" — it's quota slowly filling up with
things nobody's actively using: Jobs left in `Completed` state (their Pods
still count against quota until garbage-collected), a canary Deployment
someone forgot to clean up, or gradual replica growth from autoscaling
that nobody budgeted quota for. The failure then lands on whoever happens
to deploy next, with no obvious connection to what actually consumed the
capacity — which is exactly why `kubectl describe resourcequota` (to see
current usage) and `kubectl get pods,jobs -n <ns>` (to see what's actually
using it) are the first two commands, not guessing at RBAC or syntax.

## Go deeper

- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/concepts/policy/resource-quotas/ — the authoritative reference for ResourceQuota scopes, enforcement, and the compute-resource requirement rule.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/debug/ — general troubleshooting methodology for reasoning through "why did my create/apply fail."
- **Book:** *Kubernetes in Action* — Marko Lukša — covers ResourceQuota and LimitRange together, including how they interact.
- **Book:** *Kubernetes Patterns* — Bilgin Ibryam & Roland Huß (O'Reilly) — covers resource management patterns for multi-tenant clusters.
- **YouTube:** That DevOps Guy (Marcel Dempers) — https://www.youtube.com/@MarcelDempers — hands-on videos on Kubernetes resource management and admission control.
