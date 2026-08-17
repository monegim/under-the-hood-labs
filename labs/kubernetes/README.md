# Level 5 — Kubernetes

20 labs diagnosing real Kubernetes failure modes on a `kind`
(Kubernetes in Docker) cluster — not "how do Pods/Services work"
(that's already covered by
[`labs/linux/06-kubernetes-internals`](../linux/06-kubernetes-internals),
a Level 1 foundations lab worth doing first if you haven't), but the
kind of incidents that show up once a cluster is actually running real
workloads: broken pod-to-pod networking, DNS failures, a full etcd,
expired certificates, stuck storage, resource pressure, CNI failures,
broken ingress, and a control plane that's the incident itself.

Each lab follows the same format as every other level in this repo:
`README.md` (objective, why it matters, a numbered build, then 2
"break it" challenges with no answers given), `solution.md` (a
postmortem-style diagnosis per challenge), `CONCEPTS.md` (the underlying
mechanism explained properly, plus curated resources to go deeper),
`setup.sh` (builds the incident), and `check.sh`/`reset.sh` (verify it's
fixed / rebuild it from scratch).

## Labs

1. [`01-pod-networking-broken`](01-pod-networking-broken) — a
   `NetworkPolicy` default-deny with a missing allow rule silently drops
   pod-to-pod traffic; contrasted with a Service selector mismatch.
2. [`02-coredns-failure`](02-coredns-failure) — a bad custom `forward`
   directive in the CoreDNS `Corefile` breaks in-cluster DNS while direct
   pod-IP connectivity keeps working.
3. [`03-etcd-full`](03-etcd-full) — etcd hits its backend storage quota
   and goes into a `NOSPACE` alarm, rejecting all writes cluster-wide
   while reads keep working fine.
4. [`04-certificate-expired`](04-certificate-expired) — an admission
   webhook's TLS certificate expires, breaking every API request that
   matches its rules with an x509 handshake error.
5. [`05-pvc-stuck`](05-pvc-stuck) — a PVC stuck `Pending` from a
   nonexistent StorageClass, and a `Retain`-policy PV stuck `Released`
   blocking reuse.
6. [`06-node-pressure`](06-node-pressure) — a node under real
   `MemoryPressure`/`DiskPressure` triggers kubelet eviction, and QoS
   class decides who gets evicted first.
7. [`07-cni-failure`](07-cni-failure) — a deliberately tiny pod CIDR runs
   out of IPs, and a broken CNI config file on the node blocks pod
   networking entirely.
8. [`08-ingress-broken`](08-ingress-broken) — an Ingress with a wrong
   backend Service, and a silent `IngressClass` mismatch the controller
   never even notices.
9. [`09-api-server-unavailable`](09-api-server-unavailable) — the API
   server itself goes down; the one lab where `kubectl` stops working
   and node-level tools (`crictl`, kubelet logs, static pod manifests)
   are all you have.
10. [`10-hpa-not-scaling`](10-hpa-not-scaling) — a `HorizontalPodAutoscaler`
    sits forever unable to scale because the cluster has no metrics
    pipeline at all; fixed by installing `metrics-server` correctly,
    including the flag `kind` specifically requires.
11. [`11-resource-quota-exceeded`](11-resource-quota-exceeded) — a
    namespace `ResourceQuota` blocks a new Pod with `Forbidden`, easily
    mistaken for an RBAC or syntax problem instead of a used-vs-hard
    capacity limit.
12. [`12-admission-webhook-misconfigured`](12-admission-webhook-misconfigured) —
    a `ValidatingWebhookConfiguration` pointing at the wrong Service, with
    `failurePolicy: Fail`, blocks every matching API request cluster-wide
    with a generic connection error.
13. [`13-statefulset-pvc-mismatch`](13-statefulset-pvc-mismatch) — scaling a
    `StatefulSet` down and back up reattaches the old PVC (and its data) to
    the returning Pod, since PVCs aren't deleted on scale-down by default.
14. [`14-pdb-blocking-drain`](14-pdb-blocking-drain) — a
    `PodDisruptionBudget` with `minAvailable: 1` correctly blocks
    `kubectl drain` on a single-replica Deployment's only Pod — the PDB
    doing its job, not a bug to force through.
15. [`15-rbac-misconfiguration`](15-rbac-misconfiguration) — a Pod's
    ServiceAccount with no `Role`/`RoleBinding` fails every API call with
    `Forbidden`; contrasted with a `RoleBinding` whose `roleRef` silently
    points at nothing, and a `ClusterRole` whose reach is capped by
    *where* it's bound, not what it references.
16. [`16-probe-misconfiguration`](16-probe-misconfiguration) — a
    `livenessProbe` with timing copy-pasted from a faster service causes
    kubelet to kill and restart a perfectly healthy, just-occasionally-slow
    container on a loop.
17. [`17-taints-tolerations-mismatch`](17-taints-tolerations-mismatch) — a
    legitimately-tainted node leaves an ordinary Pod stuck `Pending`
    forever with no error anywhere in the Pod spec itself.
18. [`18-kubelet-cert-rotation-failure`](18-kubelet-cert-rotation-failure) —
    kubelet's own client certificate to the API server breaks, and the
    node goes `NotReady` while the node and kubelet process are both
    still completely alive underneath.
19. [`19-image-pull-failure`](19-image-pull-failure) — a typo'd image tag
    produces `ImagePullBackOff`; contrasted with an unreachable registry
    host (a DNS/connection failure, not "not found") and `kind`'s
    separate-per-node image store tripping up `imagePullPolicy: Never`.
20. [`20-scheduler-cannot-place-pod`](20-scheduler-cannot-place-pod) — a
    Pod requesting more CPU than any node has sits `Pending` forever
    with a perfectly valid spec; contrasted with a `nodeSelector`
    matching no node's labels, and existing workloads already claiming
    the capacity a brand-new, perfectly reasonable request needs.

## Prerequisites

- Docker installed and running
- [`kind`](https://kind.sigs.k8s.io/) (Kubernetes in Docker)
- `kubectl`

Every lab's `setup.sh` creates its own kind cluster (each lab uses a
different cluster name, so labs don't interfere with each other) and
tears it down/recreates it via `reset.sh` when you want a clean retry.
