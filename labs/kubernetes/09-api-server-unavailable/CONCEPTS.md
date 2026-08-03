# Lab 9 — Concept: The API Server Is Just a Static Pod, and kubectl Is Just Its Client

## What's actually going on

Everything every other lab in this level teaches assumes `kubectl`
works — it's the tool you use to observe and fix a cluster. This lab
breaks the one component that assumption depends on. In a kubeadm-based
cluster (which is exactly what kind runs), the API server isn't
special infrastructure living outside the cluster — it's a **static
pod**, defined by a plain manifest file
(`/etc/kubernetes/manifests/kube-apiserver.yaml`) that kubelet watches
directly on disk, independent of the API server even existing. kubelet
starts, monitors, and restarts static pods purely from that file, with
no scheduler and no API server involvement required for their basic
lifecycle — which is precisely why editing that file and having kubelet
notice and act on the change (Steps 1 and 5) works at all: it's a
mechanism specifically designed to bootstrap and self-heal the control
plane without depending on the control plane already being up. When the
manifest tells the API server to reach etcd on the wrong port, or to
load a client CA file that doesn't exist, the container starts, fails
(at a different stage for each of those two cases), exits, and kubelet
— per ordinary container restart policy — starts it again, forever,
producing an ordinary `CrashLoopBackOff` for a component that happens to
be the one everything else depends on.

`kubectl` itself has no special access to a cluster beyond being an
HTTPS client of the API server, using the same kubeconfig-based
credentials any other client would. When the API server is down, `kubectl`
fails in exactly the mundane way any HTTP client fails against a dead
server — connection refused, or a timeout — regardless of which
`kubectl` subcommand you run, because every single one of them is just a
different HTTP request to the same unreachable endpoint. This is the
core reframe this lab is built around: nothing about "the cluster is
down" from `kubectl`'s perspective tells you anything about what's
actually wrong at the node level, because `kubectl` was never capable of
seeing the node level directly in the first place — it only ever saw the
API server's view of the world, and that view is exactly what just
disappeared.

Everything this lab uses instead — `docker exec` into the node
container, `crictl` (a CLI that talks directly to the container
runtime's own gRPC socket, entirely bypassing Kubernetes' API layer),
`journalctl -u kubelet` (kubelet's own systemd-managed logs), and reading
the static pod manifest as a plain file — all operate at a layer below
the API server entirely, which is exactly why they keep working when
nothing routed through `kubectl` does. This is the same "peel back one
layer" instinct as `nsenter`-ing into a pod's network namespace in the
[Kubernetes Internals lab](../../linux/06-kubernetes-internals): Kubernetes'
own abstractions are convenient until the specific component providing
them is the thing that's broken, at which point the only way forward is
dropping to whatever's running underneath.

## Where this shows up in the real world

A managed control plane going unreachable — a cloud provider's hosted API
server having an incident, a self-managed control plane node running out
of disk or losing network connectivity, a bad manifest change during a
manual control-plane upgrade — is one of the more alarming classes of
Kubernetes incident precisely because your normal tools (`kubectl`,
dashboards backed by the API, anything watching/listing objects) all go
dark simultaneously. Experienced SREs specifically know to fall back to
node-level access (SSH, cloud console serial access, `crictl`/`journalctl`
on control-plane nodes) rather than assuming there's nothing to do until
someone else fixes it — and knowing that a static pod manifest edit is
reversible without any API server involvement at all is often the actual
fix, not just a diagnostic step.

## Go deeper

- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/ — the authoritative reference for how static pods work and why they don't depend on the API server for their basic lifecycle.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/debug/debug-cluster/ — the official guide to debugging a cluster when normal tooling is impaired.
- **Website/docs:** kind docs — https://kind.sigs.k8s.io/docs/user/known-issues/ — known kind-specific quirks worth being aware of when treating a kind node like a real control-plane node.
- **Book:** *Kubernetes in Action* — Marko Lukša — covers the kubeadm static-pod control-plane architecture this lab exercises directly.
- **YouTube:** CNCF — https://www.youtube.com/@cloudnativefdn — several KubeCon talks cover control-plane architecture and real control-plane incident stories.
