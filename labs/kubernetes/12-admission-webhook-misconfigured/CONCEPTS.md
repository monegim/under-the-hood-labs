# Lab 12 — Concept: Every Matching Request Blocks on the Webhook Call, Cluster-Wide

## What's actually going on

A `ValidatingWebhookConfiguration` (or `MutatingWebhookConfiguration`)
tells the API server: "before you finish processing any request matching
these rules, pause and make an outbound HTTPS call to this backend, and
wait for its answer." That outbound call happens synchronously, inline,
as part of handling the original request — there's no queue, no retry
loop running separately, no async reconciliation. If the API server can't
successfully complete that HTTPS round trip, it has exactly two options,
controlled by `failurePolicy`: `Fail` means treat the inability to reach
the webhook as a rejection of the original request (fail closed — safer
for security-critical webhooks, but an outage in the webhook becomes an
outage in everything it matches); `Ignore` means proceed as if the webhook
had approved it (fail open — the cluster stays usable, but the webhook is
now enforcing nothing for as long as it's unreachable). Neither is
"correct" universally; it's a deliberate tradeoff every webhook owner has
to choose, and this lab's `Fail` setting is why one bad `clientConfig`
value takes down every matching request cluster-wide instead of just
degrading gracefully.

`clientConfig.service` is a three-part reference — `name`, `namespace`,
`port` — that the API server resolves the same way any other in-cluster
client would resolve a Service: through the Service's ClusterIP and port
mapping, not a direct Pod address. That means it can break in exactly the
ways any other Service-fronted call can break, each with a distinct
signature: a `name` that doesn't match any real `Service` object fails
before any network call even happens (the API server can't resolve a
target at all); a `port` number the `Service` doesn't expose in
`spec.ports` fails the same way, for the same reason, even though the
Service itself exists; and a correctly-referenced Service with zero Ready
endpoints behind it (Pod crashed, scaled to 0, still starting) produces an
instant TCP-level refusal, because kube-proxy installs a reject rule for
ClusterIPs with no backing endpoints rather than forwarding anywhere. All
three produce some flavor of "couldn't call the webhook," but they're
different bugs at different layers, and `kubectl describe
validatingwebhookconfigurations`/`get svc`/`get endpoints` in sequence is
how you tell them apart instead of guessing.

The reason this can masquerade as "the whole API server is broken" is
scope: a webhook's `rules` can match a resource type with no namespace
restriction at all (as this lab's does — `CREATE` on ConfigMaps,
cluster-wide), so every single matching request from every user in every
namespace hits the same broken call. Nothing about the *symptom* points at
"one webhook object is wrong" — every affected request just fails with a
generic connection error, and unless you already know to check
`kubectl get validatingwebhookconfigurations`/`mutatingwebhookconfigurations`
early, it's easy to burn time assuming etcd, the scheduler, or the API
server's own health is the problem, when the API server is actually
working exactly as configured.

## Where this shows up in the real world

Admission webhooks are how most policy-enforcement tooling integrates
with Kubernetes — OPA Gatekeeper, Kyverno, cert-manager's own webhook,
Istio's sidecar injector, custom internal policy engines. All of them
register `failurePolicy: Fail` webhooks on purpose, because a policy
engine that fails open defeats its own point. The recurring incident is a
deploy or upgrade of the webhook's own backend (a Helm chart bump, a
namespace rename, a Service getting recreated with a new name) that
doesn't update every `*WebhookConfiguration` referencing it in lockstep —
and because the webhook and the thing it blocks are two separate objects
with no built-in consistency check between them, Kubernetes will happily
let you update one without the other, silently breaking everything the
stale reference used to point at correctly.

## Go deeper

- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/ — the authoritative reference for `clientConfig`, `failurePolicy`, and the admission webhook request/response lifecycle.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/debug/ — general troubleshooting methodology, including reasoning about "is this actually the API server, or something in its request path."
- **Book:** *Kubernetes in Action* — Marko Lukša — covers the admission control chain (authentication -> authorization -> admission) that webhooks plug into.
- **Book:** *Kubernetes Patterns* — Bilgin Ibryam & Roland Huß (O'Reilly) — covers policy-enforcement patterns including webhook-based validation.
- **YouTube:** That DevOps Guy (Marcel Dempers) — https://www.youtube.com/@MarcelDempers — hands-on admission controller and webhook internals videos.
