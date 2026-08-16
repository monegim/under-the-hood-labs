# Lab 12 — Admission Webhook Misconfigured (Unreachable Service)

## Objective
Register a `ValidatingWebhookConfiguration` whose `clientConfig.service`
points at the wrong Service name, with `failurePolicy: Fail`, and watch it
block every matching API request cluster-wide with a generic connection
error — then diagnose it with `kubectl get validatingwebhookconfigurations`
instead of assuming the API server itself is broken.

## Why this matters
This is deliberately a different failure from
[Lab 4](../04-certificate-expired), which breaks a webhook's TLS
certificate. Here the certificate is perfectly valid — the webhook backend
is simply unreachable, because its `clientConfig.service` reference names
a Service that doesn't exist (or the right Service with the wrong port).
The resulting error has nothing to do with certificates: it's a plain
connection failure, and because `failurePolicy: Fail` is a legitimate,
common production setting (you generally *want* a security-critical
webhook to fail closed), one wrong Service name in one webhook object can
make it look like the entire API server has stopped working — every
`kubectl create`/`apply` that matches the webhook's rules fails, on every
namespace, for every user, and the actual broken object
(`ValidatingWebhookConfiguration`) is easy to overlook because it's not
the thing anyone was trying to create.

## Prerequisites
- Docker installed and running
- `kind`, `kubectl`, and `openssl` (or just Docker — `setup.sh` generates
  the webhook's TLS cert inside a disposable container)

Check first:
```bash
docker version
kind version 2>/dev/null || echo "kind not installed"
kubectl version --client 2>/dev/null || echo "kubectl not installed"
```

Cluster creation (handled for you by `setup.sh`):
```bash
kind create cluster --name k8s12
```

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates the `k8s12` kind cluster, then in a namespace called `guard`:
- generates a valid (not expired) self-signed CA and server certificate
  in a throwaway container
- deploys a small stdlib-only Python HTTPS server that correctly answers
  `AdmissionReview` requests (always `allowed: true`) on port `8443`,
  with a `Service` called `guard-webhook` in front of it on port `443`
- confirms the webhook works end to end while everything is wired up
  correctly (baseline: creating a ConfigMap anywhere succeeds)
- registers a `ValidatingWebhookConfiguration` named
  `guard-block-configmaps`, matching `CREATE` on ConfigMaps
  **cluster-wide** (no namespace restriction), `failurePolicy: Fail`, with
  `clientConfig.service.name` set to `guard-webhook-svc` — a Service name
  that does not exist (the real one is `guard-webhook`)

## Step 2 — Confirm the symptom
```bash
kubectl --context kind-k8s12 -n default create configmap test-cm --from-literal=foo=bar
```
This fails. Try it in a completely unrelated namespace too:
```bash
kubectl --context kind-k8s12 -n kube-node-lease create configmap test-cm-2 --from-literal=foo=bar
```
Same failure, everywhere — this isn't scoped to one namespace or one
object. The error mentions failing to call a webhook, not anything about
ConfigMaps being invalid.

## Step 3 — Find which webhook is in the way
```bash
kubectl --context kind-k8s12 get validatingwebhookconfigurations
kubectl --context kind-k8s12 get validatingwebhookconfigurations guard-block-configmaps -o yaml
```
This shows `failurePolicy: Fail` (why this blocks the request outright
rather than just logging a warning) and, under `clientConfig.service`, the
exact Service name/namespace/port the API server is trying to call.

## Step 4 — Confirm the Service reference is actually wrong
```bash
kubectl --context kind-k8s12 -n guard get svc
kubectl --context kind-k8s12 get validatingwebhookconfigurations guard-block-configmaps \
  -o jsonpath='{.webhooks[0].clientConfig.service.name}{"\n"}'
```
`get svc` in the `guard` namespace lists `guard-webhook` — but the
webhook config references `guard-webhook-svc`. Two similar-looking names,
only one of which actually exists.

## Step 5 — Fix it: point the webhook at the real Service
```bash
kubectl --context kind-k8s12 patch validatingwebhookconfigurations guard-block-configmaps --type=json -p='[
  {"op":"replace","path":"/webhooks/0/clientConfig/service/name","value":"guard-webhook"}
]'
kubectl --context kind-k8s12 -n default create configmap test-cm-3 --from-literal=foo=bar
```
This now succeeds immediately — no rollout or wait needed, since nothing
about the webhook Pod or Service itself was ever broken, only the
reference pointing at it.

> **Emergency mitigation, if you can't fix the reference right away:**
> `kubectl patch validatingwebhookconfigurations guard-block-configmaps
> --type=json -p='[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Ignore"}]'`
> unblocks the cluster immediately by making the webhook fail *open*
> instead of closed — but it also means the webhook enforces nothing at
> all until you fix the real reference and set `failurePolicy` back to
> `Fail`. Treat this as a temporary, deliberate tradeoff, not the fix.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the Service name is right, but the port isn't:**
```bash
bash -c '
CTX=kind-k8s12
kubectl --context $CTX patch validatingwebhookconfigurations guard-block-configmaps --type=json -p="[
  {\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/service/name\",\"value\":\"guard-webhook\"},
  {\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/service/port\",\"value\":8443}
]"
kubectl --context $CTX -n default create configmap test-cm-portbug --from-literal=foo=bar
'
```
`clientConfig.service.name` now correctly says `guard-webhook` — and it
still fails. Compare the error text to Step 2 closely; it's not identical.
Check `kubectl --context kind-k8s12 -n guard get svc guard-webhook -o
yaml` and figure out exactly what port `8443` refers to from the API
server's point of view, versus what port the `Service` object actually
exposes.

**Challenge B — the Service exists and is correctly referenced, but nothing is behind it:**
```bash
bash -c '
CTX=kind-k8s12
kubectl --context $CTX patch validatingwebhookconfigurations guard-block-configmaps --type=json -p="[
  {\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/service/name\",\"value\":\"guard-webhook\"},
  {\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/service/port\",\"value\":443}
]"
kubectl --context $CTX -n guard scale deployment guard-webhook --replicas=0
sleep 5
kubectl --context $CTX -n default create configmap test-cm-noendpoints --from-literal=foo=bar
'
```
The webhook config now looks completely correct on paper — right Service,
right port. It still fails. Check `kubectl --context kind-k8s12 -n guard
get endpoints guard-webhook` before concluding anything, and compare the
*speed* of the failure here to Steps 2-4 and Challenge A (recall
[Lab 1](../01-pod-networking-broken)'s lesson about what a Service with no
endpoints actually does).

See `solution.md` only after you've formed your own diagnosis.
