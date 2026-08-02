# Lab 6 — Concept: Kubernetes Networking Is Namespaces + iptables, Not Magic

## What's actually going on

Everything you did in this lab is a composition of primitives from Labs 1
and 4, run by automated controllers instead of by hand. A kind "node" is
just a Docker container running `containerd` and `kubelet` — same
`struct net`-per-container model as every lab before this one, sharing your
host's kernel. There's no hypervisor boundary between "node" and "not
node"; the isolation is the same namespace mechanism you already built by
hand in Lab 1, just wrapped in a distribution that ships its own control
plane.

A pod's "network" is one network namespace, created and owned by a
special, usually-invisible container called the pod sandbox (in `crictl
pods` terms, this is what `crictl inspectp` reports a PID for). Every
container in the pod shares that one namespace — that's the actual
definition of "containers in a pod share an IP," not some higher-level
Kubernetes abstraction. When the CNI plugin runs (on kind, this is
typically `kindnetd` or whatever CNI the distro ships), its whole job is
exactly what you did by hand in Lab 1: create a veth pair, move one end
into the pod's network namespace, attach the other end to a bridge or
route it on the host, and assign an IP. `nsenter -t <pid> -n` is not "a
neat trick for exploring pods" — it's genuinely the same `setns()` syscall
that `kubectl exec`'s networking setup and every CNI plugin use internally
to operate inside a pod's namespace.

A Kubernetes Service's ClusterIP is not a real interface anywhere — it's a
virtual IP that only exists as match criteria in `iptables` rules.
kube-proxy watches the API server for Service and Endpoints/EndpointSlice
objects and, on every change, regenerates a set of chains:
`KUBE-SERVICES` catches traffic destined for a ClusterIP and jumps to a
per-Service chain (`KUBE-SVC-<hash>`), which in iptables mode uses
probability-based rules (`statistic mode random`) to pick one of several
`KUBE-SEP-<hash>` chains — one per healthy backend pod — each of which does
a plain DNAT to that pod's real IP. This is precisely the DNAT-based port
forwarding you could write by hand for any other purpose; kube-proxy's
contribution is generating and continuously reconciling those rules from
cluster state, not inventing new packet-handling mechanism. (IPVS mode
does the same job with the kernel's IP Virtual Server subsystem instead of
iptables chains, for better performance at high Service counts — same
concept, different backend.)

The two challenges expose the gap between "Kubernetes' control plane
believes X" and "X is actually true at the packet level." Endpoints are
populated only from pods that are both matched by the Service's selector
and reported Ready — when none exist, kube-proxy deliberately installs a
`REJECT` in place of what would have been a DNAT target, so clients get
instant `ECONNREFUSED` instead of a silent black hole. And kubelet's
Ready/Running status is entirely a function of whichever probes are
*configured* — by default, essentially "is the container process alive."
Taking `eth0` down inside the pod's namespace doesn't touch the container
process at all, so nothing kubelet checks by default ever notices; the
pod's namespace is broken but its `task_struct` is fine. This is exactly
why liveness/readiness probes that actually exercise the network path (an
HTTP GET, a TCP dial) exist as a first-class Kubernetes feature — without
one, Kubernetes' own status is not proof of reachability.

## Where this shows up in the real world

"Service returns connection refused" and "pod is Running but unreachable"
are two of the most common real cluster incidents, and both map directly
onto what you reproduced: a bad label selector, a failed rollout leaving
zero Ready pods, or a readiness probe that's too strict all produce the
Challenge-A symptom; a CNI plugin bug, a half-applied NetworkPolicy, or a
node's underlying veth/bridge getting into a bad state all produce the
Challenge-B symptom. Engineers who know "ClusterIP is just iptables DNAT"
and "Ready is just whatever probe you configured" go straight to `kubectl
get endpoints` and to checking the actual pod network namespace; engineers
who think of Services and Pod status as opaque Kubernetes magic end up
restarting things at random.

## Go deeper

- **Book:** *Kubernetes in Action* — Marko Lukša — walks through exactly this stack (pod networking, kube-proxy, Services) from first principles rather than treating it as a black box.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/concepts/ — the Services, Networking, and kubelet/probes sections document the exact mechanisms this lab exercises.
- **Website/blog:** iximiuz Labs — https://iximiuz.com/en/posts/ — several posts build Kubernetes pod networking up from raw namespaces and veth pairs, the same progression as Labs 1 and 4 into this one.
- **YouTube:** That DevOps Guy (Marcel Dempers) — https://www.youtube.com/@MarcelDempers — hands-on Kubernetes networking/internals videos, including kube-proxy and CNI deep dives.
- **YouTube:** David Bombal — https://www.youtube.com/@davidbombal — has Kubernetes networking walkthroughs aimed at people coming from a traditional networking background.
