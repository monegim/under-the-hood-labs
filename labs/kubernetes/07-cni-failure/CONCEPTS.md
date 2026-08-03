# Lab 7 — Concept: IPAM Is a Finite Range, and CNI Config Is Just Files on the Node

## What's actually going on

Every node in a Kubernetes cluster is assigned a slice of the cluster's
overall pod CIDR — `spec.podCIDR` on the `Node` object, handed out by the
controller manager's node-IPAM controller based on `--cluster-cidr` and
`--node-cidr-mask-size` (kubeadm/kind default to a `/24` per node out of
a `/16` cluster range, which is why this lab deliberately shrinks the
whole cluster's `podSubnet` down to a single `/27` to make exhaustion
reachable in a lab session instead of requiring hundreds of pods). Within
that per-node slice, the actual job of "hand this specific new pod an
unused IP address" belongs to the CNI plugin's IPAM component — on kind,
that's the `host-local` IPAM plugin, which tracks allocated addresses as
plain files on the node's disk (one file per allocated IP, under a
directory like `/var/lib/cni/networks/<network-name>/`). When every
address in the range is already checked out to some other pod, the next
`ADD` call has nothing left to hand back, and returns exactly the error
this lab reproduces — `failed to allocate for range 0: no IP addresses
available in range set` — which kubelet surfaces directly into the pod's
Events, unmodified, because kubelet itself doesn't understand IPAM
internals any more than it understands what image a container runs; it's
just relaying whatever the CNI plugin told it.

This is a genuinely different kind of failure from a CNI plugin that
can't run *at all*, which is what Challenge B reproduces. Kubelet decides
whether it's even ready to run pod networking setup by checking for a
valid CNI configuration file under `/etc/cni/net.d/` — if none exists (or
none parses), kubelet reports the node's network plugin as not ready,
and every single new pod fails immediately, regardless of how much of
the pod CIDR is actually free. Exhaustion (Step 3) is a resource-full
failure inside a working system; a missing/broken CNI config is a
missing-component failure that breaks the whole node's pod networking
capability from the first attempt. Kind's own bundled CNI (`kindnetd`,
which wraps standard `ptp`/`host-local` CNI plugins rather than
inventing new mechanism, as covered in the
[Kubernetes Internals lab](../../linux/06-kubernetes-internals)) writes
exactly this kind of conflist file at node startup — moving or corrupting
it reproduces, on a toy cluster, the same class of incident a real broken
CNI plugin rollout or a misconfigured `/etc/cni/net.d/` file causes on
any Kubernetes node.

Both failures ultimately show up as a pod stuck in the exact same visible
phase (`ContainerCreating`), which is precisely why `kubectl describe
pod`'s Events section — not the pod's phase or status alone — is the
only reliable way to tell them apart, and matters for figuring out
whether the fix is "free up capacity" (Step 5/Challenge A) or "restore a
missing file on the node" (Challenge B). Neither symptom implies anything
is wrong with the pod spec itself, which is exactly the trap:
`ContainerCreating` invites checking the pod's own definition first, when
the actual cause lives entirely at the node/CNI layer.

## Where this shows up in the real world

Pod CIDR exhaustion is a real capacity-planning failure in dense
clusters — undersized `--node-cidr-mask-size` choices made early in a
cluster's life (often copied from a smaller reference cluster) become a
hard ceiling on pods-per-node that only becomes visible once a node
actually tries to run that many pods, often during a scale-up event or
after enabling a DaemonSet that adds one more pod to every node. Broken
CNI configuration is a common failure mode after CNI plugin upgrades or
node provisioning changes — a CNI DaemonSet rollout that fails partway,
a golden-image change that drops the wrong config file, or a
node-bootstrapping script race condition where kubelet starts before the
CNI plugin has finished writing its config. Both are node-level, not
pod-level, which is why they're diagnosed the same way (checking the
node and its CNI state directly) even though the underlying cause is
completely different.

## Go deeper

- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/concepts/cluster-administration/networking/ — the authoritative overview of cluster networking, pod CIDR allocation, and CNI's role.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/debug/ — general troubleshooting task index this lab's diagnostic sequence follows.
- **Website/docs:** kind docs — https://kind.sigs.k8s.io/docs/user/configuration/ — `podSubnet`/`disableDefaultCNI` configuration used to build this lab's tiny-range scenario.
- **Website/blog:** Learnk8s blog — https://learnk8s.io/blog — has practical posts on Kubernetes networking and CNI failure diagnosis.
- **YouTube:** That DevOps Guy (Marcel Dempers) — https://www.youtube.com/@MarcelDempers — hands-on CNI/IPAM internals and troubleshooting videos.
