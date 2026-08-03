# Level 5 — Kubernetes

Nine labs diagnosing real Kubernetes failure modes on a `kind`
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

## Prerequisites

- Docker installed and running
- [`kind`](https://kind.sigs.k8s.io/) (Kubernetes in Docker)
- `kubectl`

Every lab's `setup.sh` creates its own kind cluster (each lab uses a
different cluster name, so labs don't interfere with each other) and
tears it down/recreates it via `reset.sh` when you want a clean retry.
