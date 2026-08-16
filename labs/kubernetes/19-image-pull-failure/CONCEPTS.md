# Lab 19 — Concept: Three Layers, One Status String

## What's actually going on

When a Pod is scheduled, the kubelet on its assigned node is responsible
for getting the container image ready before it can start anything. That
process has distinct stages — resolve the image reference to a
registry, connect to that registry, ask it whether the specific tag
exists, download and unpack the layers if so — and a failure at any
stage gets folded into the same two status strings Kubernetes surfaces
at the Pod level: `ErrImagePull` (the current attempt failed) and
`ImagePullBackOff` (retrying with exponential backoff after repeated
failures). That collapsing is deliberate — `kubectl get pods` is meant
to be a fast overview, not a diagnosis — but it means the status column
alone cannot distinguish "wrong tag" from "unreachable registry" from
"local-only image policy violated," even though those are three
different problems requiring three different people/fixes. The actual
diagnosis always lives one level deeper, in the Events section of
`kubectl describe pod`, which preserves the kubelet's own error text
almost verbatim.

`imagePullPolicy` decides *whether the kubelet is even allowed to try
pulling* in the first place, independent of whether the image exists
anywhere. `Always` unconditionally re-pulls, checking the registry every
time (mainly useful for mutable tags like `latest`, at the cost of a
network round-trip on every Pod start). `IfNotPresent` (the default when
a tag is specified) only pulls if the image isn't already present in that
node's local image store — fast, but means a node with a stale cached
image under the same tag won't notice a newer version exists remotely.
`Never` forbids pulling entirely, under any circumstance — the image
must already be present locally, full stop, or the Pod fails with
`ErrImageNeverPull` before any network request happens at all. This is
what makes Challenge B's failure look nothing like a registry problem:
mechanically, no registry was ever contacted.

`kind` clusters make the local-image-store distinction concrete and easy
to trip over: each "node" `kind` creates is itself a Docker container,
running its own containerd daemon with its own separate image store —
entirely disconnected from the host machine's Docker image store, even
though both are "on the same machine" from a human's point of view.
Building an image with `docker build` on the host populates the host's
store; a `kind` node's containerd has no visibility into that store at
all. `kind load docker-image` exists specifically to bridge this gap —
it exports the image from the host's Docker daemon and imports it
directly into every node's containerd store, without ever touching a
registry, which is why it works even for images that were never pushed
anywhere.

## Where this shows up in the real world

"Not found" failures are usually a CI/CD or release-process bug — a
deploy manifest referencing a tag that was never actually built and
pushed, or a tag that existed and was later deleted by a registry
retention policy while something still referenced it. Registry
unreachability failures point outward from the cluster entirely — DNS
misconfiguration, a firewall or NetworkPolicy blocking egress to the
registry, or a genuine upstream registry outage — and are a common cause
of a whole node pool (or a whole cluster, if the base OS images are
affected too) failing to schedule anything new all at once, which reads
very differently from one Deployment's Pod being stuck. The `kind`
local-image gap is specific to local development and CI pipelines that
use `kind` — it's one of the most frequently asked "why doesn't my
cluster see the image I just built" questions for anyone new to
`kind`-based local Kubernetes development.

## Go deeper

- **Website/docs:** Kubernetes docs, Images — https://kubernetes.io/docs/concepts/containers/images/ — the authoritative reference for `imagePullPolicy` semantics and image reference resolution.
- **Website/docs:** Kubernetes docs, Debug Running Pods — https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/ — general methodology for reading Pod status and Events, applicable well beyond image-pull issues.
- **Website/docs:** kind docs, Loading an Image Into Your Cluster — https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster — the authoritative reference for `kind load docker-image` and why it's necessary.
- **Website/docs:** kind docs, Local Registry — https://kind.sigs.k8s.io/docs/user/local-registry/ — the alternative approach (a real local registry container) for teams that want registry-backed workflows instead of `kind load`.
- **Blog:** Learnk8s, "Kubernetes Troubleshooting: ImagePullBackOff" — https://learnk8s.io/troubleshooting-deployments — general Pod-failure troubleshooting flowchart that places image-pull failures in context with other Pod startup failure modes.
