# Lab 1 — Concept: NetworkPolicies Are Enforced by the CNI Plugin, Not the API Server

## What's actually going on

A `NetworkPolicy` object, once created, is just data sitting in etcd —
the API server does not enforce it, and neither does kube-proxy. Actual
enforcement is entirely the CNI plugin's job: it watches the API server
for `NetworkPolicy`, `Pod`, and `Namespace` objects and translates them
into packet-filtering rules on each node (iptables/nftables chains for
Calico's default backend, eBPF programs for Calico's eBPF dataplane or
Cilium). This is exactly why kind's default CNI, `kindnetd`, silently does
nothing with `NetworkPolicy` objects — it's a minimal CNI focused on basic
pod connectivity and doesn't implement policy enforcement at all. You can
`kubectl apply` a `NetworkPolicy` against a `kindnetd` cluster all day and
traffic will flow exactly as if it didn't exist, with no error or warning
anywhere. That's why this lab disables kind's default CNI and installs
Calico — without a policy-aware CNI, there is nothing to actually break.

Once a policy-aware CNI is in place, a `NetworkPolicy` with `policyTypes:
[Ingress]` and no `ingress` rules (or an empty `podSelector: {}` selecting
every pod in the namespace) is a **default-deny**: every pod it selects
now drops all incoming traffic except what's explicitly allowed by some
*other* policy's `ingress.from` rules. Policies are additive — multiple
policies selecting the same pod all get OR'd together — so "add the
missing allow rule" (Step 5) works by adding a second policy alongside the
deny, not by editing the deny policy itself. Critically, an `ingress.from`
`podSelector` is evaluated purely on live pod labels at the moment a
connection is attempted; there is no compile-time check that a selector
actually matches anything. A rule that references `app: front-end` when
the real label is `app: frontend` compiles and applies without complaint,
selects zero pods, and produces a policy that behaves as if it doesn't
exist — indistinguishable from the original no-allow-rule bug from the
caller's point of view.

That silent-drop behavior is also the tell for diagnosing NetworkPolicy
problems specifically: dropped-by-policy traffic times out at the TCP
level (SYN packets are dropped, so the client just waits), because the
CNI's packet filter acts below the Service/DNAT layer, on real pod IPs,
with no participant sending back a RST or ICMP unreachable. That's a
structurally different signal from a Service-selector mismatch (Challenge
B), where kube-proxy itself has no backend to forward to and deliberately
installs a `REJECT`/`ECONNREFUSED` response — an instant, explicit
rejection rather than a hang. Learning to read "hangs" vs "refuses
instantly" as evidence of *which layer* is broken (packet-filtering vs.
Service wiring) turns two visually similar symptoms into two very
different, well-scoped investigations.

## Where this shows up in the real world

Namespace-level default-deny NetworkPolicies are extremely common in
real clusters — most security baselines mandate them as a "zero trust by
default" posture. The recurring incident is exactly this lab: a team
locks down a namespace, and either forgets to add an allow rule for a
legitimate new caller, or adds one with a label selector that doesn't
match reality (a Deployment's pod-template labels changed during a
refactor, an app was renamed, a typo). Because the failure is a silent
timeout with nothing in either side's application logs, it's frequently
misdiagnosed as "the service is slow" or "DNS is broken" before someone
thinks to check `kubectl get networkpolicy` at all. Multi-tenant clusters
(shared clusters across teams) see this constantly whenever a new
cross-namespace dependency gets added without updating policy.

## Go deeper

- **Book:** *Kubernetes in Action* — Marko Lukša — covers NetworkPolicy semantics (default-deny, additive rules, selector-based scoping) in depth.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/concepts/services-networking/network-policies/ — the authoritative reference for how policies compose and what "no rules" vs. "no policies" actually means.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/debug/ — general troubleshooting methodology, including the reasoning path for "traffic isn't reaching a pod."
- **Website/blog:** Learnk8s blog — https://learnk8s.io/blog — has deep, practical posts on Kubernetes networking failure modes including policy misconfiguration.
- **YouTube:** That DevOps Guy (Marcel Dempers) — https://www.youtube.com/@MarcelDempers — hands-on NetworkPolicy and CNI internals videos.
