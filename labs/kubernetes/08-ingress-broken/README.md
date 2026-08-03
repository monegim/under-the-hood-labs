# Lab 8 — Ingress Broken (Wrong Backend, and a Silent IngressClass Mismatch)

## Objective
Install ingress-nginx on kind the documented way, break an `Ingress`
resource's backend service reference, diagnose it with
`kubectl describe ingress` and controller logs, then see a completely
different, much quieter failure: an `Ingress` the controller never even
looks at because of a missing `ingressClassName`.

## Why this matters
An `Ingress` object being wrong and an `Ingress` object being silently
ignored produce very different flavors of confusion. A bad backend
reference at least shows up as an error somewhere (in the controller's
logs, sometimes in `describe ingress` events) once you know to look —
but an `IngressClass` mismatch means the controller does absolutely
nothing with the object at all, no error, no event, nothing, because as
far as that controller is concerned the resource was never meant for it.
Telling these apart quickly (does the controller know this Ingress
exists at all, or does it know and reject it) is the entire diagnostic
skill.

## Prerequisites
- Docker installed and running
- `kind` and `kubectl`

Check first:
```bash
docker version
kind version 2>/dev/null || echo "kind not installed"
kubectl version --client 2>/dev/null || echo "kubectl not installed"
```

Cluster creation (this is what `setup.sh` runs for you — kind's
documented ingress-nginx setup needs `extraPortMappings` for 80/443 and
a node label the controller's node selector targets):
```bash
cat <<'EOF' > /tmp/lab-k8s08-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
EOF
kind create cluster --name k8s08 --config /tmp/lab-k8s08-config.yaml
kubectl --context kind-k8s08 apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```
(This is kind's own documented ingress-nginx recipe — see
https://kind.sigs.k8s.io/docs/user/ingress/ and the
[ingress-nginx deploy manifests](https://github.com/kubernetes/ingress-nginx/blob/main/deploy/static/provider/kind/deploy.yaml).
If port 80/443 are already in use on your machine, change the
`hostPort` values above.)

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates the `k8s08` kind cluster + ingress-nginx as above, waits for
the controller to be Ready, deploys an `nginx` backend + Service
(`web-svc`, port 80), then creates an `Ingress` whose backend
`service.name` points at a Service that doesn't exist (`web-svc-typo`).

## Step 2 — Confirm the symptom
```bash
curl -sS -H "Host: lab8.local" http://localhost/
```
This returns a `503 Service Temporarily Unavailable` from ingress-nginx
itself (not from your app — nginx is answering, it just has nowhere to
send the request).

## Step 3 — Check the Ingress object
```bash
kubectl --context kind-k8s08 describe ingress web-ingress
```
Recent Kubernetes versions surface a validation-time event here for an
obviously missing backend Service, but check the controller's own logs
too — it's the more reliable signal:
```bash
kubectl --context kind-k8s08 -n ingress-nginx logs -l app.kubernetes.io/component=controller --tail=30 | grep -i "web-svc\|error"
```
The controller logs a warning about being unable to find the Service
named `web-svc-typo` for that Ingress's backend.

## Step 4 — Confirm the actual Service name
```bash
kubectl --context kind-k8s08 get svc
kubectl --context kind-k8s08 get ingress web-ingress -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}{"\n"}'
```
`web-svc` exists; `web-svc-typo` (what the Ingress actually references)
does not.

## Step 5 — Fix it
```bash
kubectl --context kind-k8s08 patch ingress web-ingress --type=json \
  -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/name","value":"web-svc"}]'
curl -sS -H "Host: lab8.local" http://localhost/
```
This should now return nginx's welcome page HTML.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — right service name, wrong port:**
```bash
kubectl --context kind-k8s08 patch ingress web-ingress --type=json \
  -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/port/number","value":8080}]'
curl -sS -H "Host: lab8.local" http://localhost/
```
Same 503-ish symptom, but check the controller logs again — the wording
is different from Step 3's "service not found." Explain exactly what's
different between "the Service doesn't exist" and "the Service exists
but doesn't expose this port," and where the real disconnect is
(`kubectl get svc web-svc -o yaml`'s `.spec.ports` versus the Ingress).

**Challenge B — IngressClass mismatch (controller ignores it entirely):**
```bash
bash -c '
CTX=kind-k8s08
kubectl --context $CTX patch ingress web-ingress --type=json \
  -p "[{\"op\":\"replace\",\"path\":\"/spec/rules/0/http/paths/0/backend/service/port/number\",\"value\":80}]"
kubectl --context $CTX get ingress web-ingress -o jsonpath="{.spec.ingressClassName}{\"\n\"}"
kubectl --context $CTX patch ingress web-ingress --type=json \
  -p "[{\"op\":\"replace\",\"path\":\"/spec/ingressClassName\",\"value\":\"does-not-exist\"}]"
curl -sS -H "Host: lab8.local" http://localhost/
kubectl --context $CTX -n ingress-nginx logs -l app.kubernetes.io/component=controller --tail=10
'
```
Compare this failure to every prior one in this lab: instead of the 503
you saw in Step 2, you now get a plain `404` from ingress-nginx's own
*default backend* (its generic "no rule matched this host" response) —
not an error about `web-ingress` at all, because as far as the
controller is concerned, no such rule exists. The controller's logs
mention this Ingress **not at all**, not even a warning. Figure out why
an IngressClass mismatch is categorically quieter than a bad backend
reference, and what `kubectl get ingressclass` tells you that
`describe ingress` alone doesn't.

See `solution.md` only after you've formed your own diagnosis.
