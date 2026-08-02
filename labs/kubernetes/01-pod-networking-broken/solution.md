# Lab 1 — Solutions

## Challenge A — allow rule exists but the label doesn't match

**Check:**
```bash
kubectl --context kind-k8s01 -n shop describe networkpolicy allow-frontend-to-backend
kubectl --context kind-k8s01 -n shop get pod frontend --show-labels
```
`describe networkpolicy` shows the rule allows ingress `From:
PodSelector: app=front-end` — but `get pod frontend --show-labels` shows
the pod is actually labeled `app=frontend` (no hyphen). The policy's
selector and the pod's real label are two different strings that happen
to look similar at a glance.

**Diagnosis:** the `NetworkPolicy`'s `podSelector` under `ingress.from` is
just a label selector — it doesn't know or care what you *meant*, only
what labels actually exist on pods right now. A selector that matches zero
pods isn't an error Kubernetes will warn you about; it just silently
allows traffic from nothing, which looks identical to "policy not applied
at all" from the caller's side.

**Fix:**
```bash
kubectl --context kind-k8s01 -n shop patch networkpolicy allow-frontend-to-backend \
  --type=json -p '[{"op":"replace","path":"/spec/ingress/0/from/0/podSelector/matchLabels/app","value":"frontend"}]'
kubectl --context kind-k8s01 -n shop exec frontend -- curl -m 3 -sS http://backend-svc
```

**Lesson:** never eyeball-compare a `NetworkPolicy`'s selector against a
pod's labels — diff them explicitly (`describe networkpolicy` next to
`get pod --show-labels`). A selector matching zero pods produces the exact
same timeout as no allow rule existing at all, so "the rule looks right"
is not a diagnosis.

---

## Challenge B — Service selector mismatch (not a NetworkPolicy issue)

**Check:**
```bash
kubectl --context kind-k8s01 -n shop get endpoints backend-svc
kubectl --context kind-k8s01 -n shop get pods --show-labels
kubectl --context kind-k8s01 -n shop exec frontend -- curl -m 3 -sS http://backend-svc
```
`get endpoints backend-svc` shows `<none>` — no backing pods at all. The
`curl` fails immediately with `Connection refused`, not a timeout.

**Diagnosis:** the Service's `spec.selector` was patched to `app:
backendd` (typo), which matches zero pods, so kube-proxy has nothing to
DNAT to and (as covered in the
[Kubernetes Internals lab](../../linux/06-kubernetes-internals)) installs
a `REJECT` rule instead of a forwarding target for that ClusterIP. This is
a completely different mechanism from Challenge A even though both
"selectors don't match": a `NetworkPolicy` selector mismatch drops packets
silently (timeout), while a Service selector mismatch means there was
never a destination to send packets to in the first place (instant
refusal).

**Fix:**
```bash
kubectl --context kind-k8s01 -n shop patch svc backend-svc -p '{"spec":{"selector":{"app":"backend"}}}'
kubectl --context kind-k8s01 -n shop get endpoints backend-svc
kubectl --context kind-k8s01 -n shop exec frontend -- curl -m 3 -sS http://backend-svc
```

**Lesson:** timeout vs. instant refusal is a real diagnostic signal, not
noise — it tells you whether you're looking for a policy/firewall problem
(packets arrive, get dropped) or a Service/endpoints problem (no
destination exists at all). Check `kubectl get endpoints <svc>` before you
go anywhere near `NetworkPolicy` objects; it takes one command and rules
out (or confirms) an entire category of cause.
