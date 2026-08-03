# Lab 8 — Solutions

## Challenge A — Service exists, but not on that port

**Check:**
```bash
kubectl --context kind-k8s08 get svc web-svc -o yaml | grep -A4 ports
kubectl --context kind-k8s08 -n ingress-nginx logs -l app.kubernetes.io/component=controller --tail=20 | grep -i web-svc
```
`web-svc`'s `.spec.ports` shows only port `80` defined. The controller's
logs this time say something like
`error obtaining Endpoints for Service "default/web-svc" ... port 8080
not found` or a similar port-specific message — clearly distinct from
Step 3's "service not found."

**Diagnosis:** "the Service doesn't exist" (Step 3) and "the Service
exists but doesn't expose this port" are different lookups entirely: the
first fails at Service-object resolution, the second fails one level
deeper, at matching the Ingress's requested port number against that
Service's actual `.spec.ports[].port` (or `.name`, if the Ingress
references a named port) list. ingress-nginx can find `web-svc` just
fine here — it just has no rule for routing to a port that isn't defined
on it.

**Fix:**
```bash
kubectl --context kind-k8s08 patch ingress web-ingress --type=json \
  -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/port/number","value":80}]'
curl -sS -H "Host: lab8.local" http://localhost/
```

**Lesson:** always check both ends of a backend reference independently
— does the Service exist, and separately, does it expose the exact port
number (or name) the Ingress asks for — because the controller's error
message genuinely differs between the two, and jumping straight to
"the Ingress's backend section is wrong" without reading which part is
wrong wastes a diagnosis step you already have the exact answer for.

---

## Challenge B — IngressClass mismatch means the controller never looks

**Check:**
```bash
kubectl --context kind-k8s08 get ingress web-ingress -o jsonpath='{.spec.ingressClassName}{"\n"}'
kubectl --context kind-k8s08 get ingressclass
kubectl --context kind-k8s08 -n ingress-nginx logs -l app.kubernetes.io/component=controller --tail=20 | grep -i web-ingress
```
`web-ingress`'s `ingressClassName` is `does-not-exist`.
`get ingressclass` shows the real one installed by ingress-nginx is
called `nginx`. Grepping the controller's logs for `web-ingress` returns
nothing at all — not a warning, not an error, no mention whatsoever.

**Diagnosis:** ingress controllers watch for `Ingress` objects whose
`spec.ingressClassName` matches an `IngressClass` they're responsible
for (this replaced the older, deprecated
`kubernetes.io/ingress.class` annotation approach). An Ingress with no
matching `IngressClass` — whether that's a typo, a class from a
different controller entirely, or simply omitted when a cluster has more
than one controller installed — is, from the controller's point of
view, not its object to process at all. It doesn't reject it, doesn't
log about it, doesn't emit an event about it; it's structurally
equivalent to the Ingress not existing as far as that specific
controller's watch loop is concerned. This is categorically quieter than
Steps 2-4 or Challenge A, where the controller at least knows the
Ingress exists and is actively trying (and failing) to route to it.

**Fix:**
```bash
kubectl --context kind-k8s08 patch ingress web-ingress --type=json \
  -p '[{"op":"replace","path":"/spec/ingressClassName","value":"nginx"}]'
curl -sS -H "Host: lab8.local" http://localhost/
```

**Lesson:** when an Ingress produces *zero* signal anywhere — no
controller log line, no event, nothing — the first check should be
`kubectl get ingress <name> -o jsonpath='{.spec.ingressClassName}'`
compared against `kubectl get ingressclass`, before assuming a backend
problem. A silent Ingress and a broken Ingress look identical from the
outside (nothing routes to your app either way) but require checking
completely different things.
