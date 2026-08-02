# Level 5 — Kubernetes (planned)

Not built yet. Planned topics: pod networking broken, CoreDNS failure,
etcd full, certificate expired, PVC stuck, node pressure, CNI failure,
ingress broken, API server unavailable.

Note: `labs/linux/06-kubernetes-internals` already exists as a Level 1
foundations lab (demystifying kubelet/CNI/kube-proxy mechanics using
`kind`) — this level is about diagnosing real k8s failure modes on top
of that foundation, not re-teaching the internals.

Will follow the same per-lab format as [Level 1](../linux) and
[Level 2](../networking): `README.md`, `solution.md`, `CONCEPTS.md`,
`setup.sh`, `check.sh`, `reset.sh`.
