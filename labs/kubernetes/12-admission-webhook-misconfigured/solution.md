# Lab 12 — Solutions

## Challenge A — right Service, wrong port

**Check:**
```bash
kubectl --context kind-k8s12 -n guard get svc guard-webhook -o yaml
kubectl --context kind-k8s12 get validatingwebhookconfigurations guard-block-configmaps \
  -o jsonpath='{.webhooks[0].clientConfig.service.port}{"\n"}'
```
`get svc guard-webhook` shows `spec.ports` with a single entry: `port:
443`. The webhook config's `clientConfig.service.port` is `8443` — a port
number the `Service` object doesn't expose at all. The error from
`create configmap` is a connection failure again, but this time it's
failing before the API server can even resolve where to send the request,
rather than timing out trying to reach something.

**Diagnosis:** `clientConfig.service.port` isn't "the port the container
listens on" — it's "the port on the `Service` object to call," exactly
like any other client talking to a ClusterIP Service. The webhook Pod
does listen on `8443` internally, but the `Service` in front of it maps
external port `443` to that container port `8443` (`port: 443` ->
`targetPort: 8443`). Pointing the webhook config at `8443` skips the
Service's port mapping entirely and asks for a port number the Service
was never configured to expose, which the API server's service resolver
rejects immediately rather than attempting a network call that was never
going to succeed.

**Fix:**
```bash
kubectl --context kind-k8s12 patch validatingwebhookconfigurations guard-block-configmaps --type=json -p='[
  {"op":"replace","path":"/webhooks/0/clientConfig/service/port","value":443}
]'
kubectl --context kind-k8s12 -n default create configmap test-cm-portfix --from-literal=foo=bar
```

**Lesson:** `clientConfig.service.{name,namespace,port}` describes a path
through the `Service` object, not a direct route to the Pod — always
cross-check it against `kubectl get svc <name> -o yaml`'s actual
`spec.ports`, the same way you'd check any other Service-fronted client
call. A webhook config with a syntactically valid but nonexistent port
number fails distinctly from — and earlier than — a genuine network
unreachability problem.

---

## Challenge B — Service correctly wired, zero endpoints behind it

**Check:**
```bash
kubectl --context kind-k8s12 -n guard get endpoints guard-webhook
kubectl --context kind-k8s12 -n guard get pods -l app=guard-webhook
```
`get endpoints` shows `<none>` — the Service's selector is fine, but there
are no Ready Pods behind it because the Deployment was scaled to 0. The
`create configmap` failure here is immediate, not a hang — an instant
refusal rather than a multi-second timeout.

**Diagnosis:** Everything about the webhook's *configuration* is now
correct — right Service name, right port, right `caBundle`. What's
missing is a running backend. With zero Ready endpoints, kube-proxy (per
[Lab 1](../01-pod-networking-broken)'s Challenge B) has nothing to
forward the connection to and installs a reject rule for that ClusterIP,
so the API server's TCP connection to the webhook Service is refused
immediately rather than hanging — the same instant-refusal signature as
any other Service-with-no-endpoints failure, just happening to be a
webhook this time instead of an application Service.

**Fix:**
```bash
kubectl --context kind-k8s12 -n guard scale deployment guard-webhook --replicas=1
kubectl --context kind-k8s12 -n guard rollout status deployment guard-webhook --timeout=60s
kubectl --context kind-k8s12 -n default create configmap test-cm-scaledback --from-literal=foo=bar
```

**Lesson:** a `ValidatingWebhookConfiguration` that looks entirely correct
in its YAML can still be broken if its backing Deployment has no Running
Pods — `kubectl describe validatingwebhookconfigurations` alone won't
show you that; you have to separately check `kubectl get
deployment`/`get endpoints` for the Service it points at, the same way you
would for any other "why can't this reach that Service" investigation.
The instant-refusal-vs-hang distinction from Lab 1 applies here just as
much as it does to application traffic.
