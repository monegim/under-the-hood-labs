# Lab 13 — Concept: StatefulSet PVCs Have a Lifecycle Independent of Their Pods

## What's actually going on

A `Deployment`'s Pods are fungible — the ReplicaSet controller creates
and deletes them from a single template, and no individual Pod's identity
matters. A `StatefulSet` exists specifically to break that assumption:
each replica gets a stable, predictable identity (`myapp-0`, `myapp-1`,
...) and, if the `StatefulSet` defines `volumeClaimTemplates`, each
ordinal also gets its own `PersistentVolumeClaim`, deterministically
named `<template-name>-<statefulset-name>-<ordinal>`. That naming is the
whole mechanism: when the `StatefulSet` controller needs to (re)create
`myapp-1`, it doesn't ask "is there a PVC for this Pod" in the abstract —
it looks for a PVC named exactly `data-myapp-1`. If one already exists
and is `Bound`, the new Pod just uses it. There's no concept of "this
PVC belonged to an old, now-deleted Pod" baked into that lookup — same
ordinal, same PVC name, same volume, regardless of how much time passed
or how many Pods have occupied that ordinal in between.

The controller's default behavior, absent any
`persistentVolumeClaimRetentionPolicy`, is to never delete a
`volumeClaimTemplate`-created PVC on its own — not on Pod deletion, not
on scale-down, not even (by default) on deleting the `StatefulSet`
itself. This is a deliberate, conservative default: a `StatefulSet`
commonly models something like a database cluster, where losing a
replica's disk because someone scaled the fleet down for an afternoon
would be a genuine data-loss incident, not a convenience. Kubernetes 1.27
made this configurable via `spec.persistentVolumeClaimRetentionPolicy`,
with two independent fields answering two independent questions:
`whenScaled` (what happens to an ordinal's PVC when `replicas` shrinks
past it) and `whenDeleted` (what happens to all remaining PVCs when the
`StatefulSet` object itself is deleted). Both default to `Retain`. Setting
either to `Delete` is an explicit, per-axis opt-in — setting `whenScaled:
Delete` says nothing about what happens on full teardown, and vice versa,
because "shrink the fleet" and "delete the whole thing" are different
operational events with potentially different intended data-safety
outcomes.

The other piece of protection sitting underneath all of this is the
`kubernetes.io/pvc-protection` finalizer, which every PVC gets
automatically the moment a Pod references it. A `kubectl delete pvc`
against an in-use PVC always succeeds in the sense that the object is
marked for deletion (`STATUS` flips to `Terminating`), but the finalizer
blocks the actual removal from etcd until no Pod references it anymore.
This is unrelated to `StatefulSet`s specifically — any PVC in use by any
Pod gets this protection — but it interacts with the retention policy
mechanics above in a way that surprises people: even a PVC that's
*supposed* to be deleted (per `whenScaled: Delete`) will sit
`Terminating` until its Pod actually finishes terminating first.

## Where this shows up in the real world

This is the exact mechanic behind two very different reactions to the
same news: "our Kafka/Postgres/Elasticsearch StatefulSet replica count
just dropped and came back and the data's still there" (expected,
working as designed, this is the point of PVC retention) versus "we
scaled down for cost savings over the weekend, scaled back up Monday, and
a replica started rejoining the cluster with days-old, badly stale data
that then had to be reconciled" (the same mechanic, but nobody expected
it, because the team's mental model was closer to a stateless
Deployment). It's a genuinely recurring incident category any time a
team treats a stateful workload's replica count as freely elastic without
first deciding, deliberately, what should happen to each ordinal's
storage on the way down.

## Go deeper

- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/ — the authoritative reference for PVC naming, ordinal identity, and `persistentVolumeClaimRetentionPolicy`.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/debug/ — general troubleshooting methodology for reasoning about stateful workload incidents.
- **Book:** *Kubernetes in Action* — Marko Lukša — covers StatefulSet identity and storage guarantees in depth.
- **Book:** *Kubernetes Patterns* — Bilgin Ibryam & Roland Huß (O'Reilly) — covers stateful service patterns, including safe scaling of stateful workloads.
- **YouTube:** That DevOps Guy (Marcel Dempers) — https://www.youtube.com/@MarcelDempers — hands-on StatefulSet and persistent storage videos.
