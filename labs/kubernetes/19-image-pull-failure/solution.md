# Lab 19 — Solutions

## Challenge A — the registry itself is the problem, not the tag

**Check:**
```bash
kubectl --context kind-k8s19 describe pod -l app=webapp | grep -A3 "Failed to pull"
```
Something like:
```
Failed to pull image "registry.internal.example.corp/webapp:v1": failed to pull and unpack image
"registry.internal.example.corp/webapp:v1": failed to resolve reference
"registry.internal.example.corp/webapp:v1": failed to do request: Head
"https://registry.internal.example.corp/v2/webapp/manifests/v1": EOF
```
No "not found" anywhere. It's failing at "resolve reference" /
"do request" — i.e. the very first network step, before the registry
ever got a chance to answer "does this image exist."

**Diagnosis:** Step 3's failure ("not found") means the request
*reached* a real registry (`docker.io`) and got a definitive answer: that
tag isn't there. This failure means the request never got a usable
answer at all — `registry.internal.example.corp` doesn't resolve to
anything reachable from this node, so there's no registry to ask in the
first place. These aren't degrees of the same problem; they're different
layers. "Not found" is an application-layer response from a real server.
This is a network/DNS-layer failure that never reached an application at
all. The exact error text (`EOF`, "no such host", "connection refused",
"i/o timeout") varies by exactly how the resolution/connection fails,
but none of it will ever mention whether the image exists, because the
registry was never asked.

**Fix:** this isn't a Kubernetes-side problem to patch — it's the image
reference pointing at a registry that either doesn't exist, isn't
reachable from this cluster's network, or was typo'd:
```bash
kubectl --context kind-k8s19 set image deployment/webapp nginx=nginx:1.27
```
(In a real environment: confirm the intended registry hostname is
correct, actually resolves from inside the cluster's network, and that
nothing — firewall, NetworkPolicy, missing DNS entry — is blocking the
node from reaching it.)

**Lesson:** "ImagePullBackOff" is a status, not a diagnosis — `kubectl
describe pod`'s Events text is what actually tells you whether you're
looking at "the image is wrong" (fix the tag) or "the registry is
unreachable" (fix networking/DNS, a completely different kind of
problem, possibly not even yours to fix if it's an upstream registry
outage).

---

## Challenge B — `kubectl describe` shows a completely different reason, no registry involved at all

**Check:**
```bash
kubectl --context kind-k8s19 describe pod local-only-app | grep -A2 "Events:"
```
```
Warning  ErrImageNeverPull  ...  Container image "local-only-app:v1" is not present with pull policy of Never
```
No mention of pulling, resolving, or any registry at all.

**Diagnosis:** `imagePullPolicy: Never` tells the kubelet, explicitly:
never attempt to pull this image under any circumstances — only use
what's already present in *this specific node's* local container
runtime, as-is. `docker build` on your own machine puts the image in
your machine's Docker image store. A `kind` cluster's "nodes" are
themselves separate containers, each running their own independent
containerd instance with its own separate image store — building an
image with your host's `docker build` does not make it appear inside a
kind node's containerd, no matter how real and present that image is on
the host. From the node's point of view, `local-only-app:v1` simply
isn't there, and `imagePullPolicy: Never` forbids the one thing
(pulling, from somewhere) that could otherwise fix that.

**Fix:**
```bash
kind load docker-image local-only-app:v1 --name k8s19
kubectl --context kind-k8s19 delete pod local-only-app
kubectl --context kind-k8s19 apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: local-only-app
spec:
  containers:
    - name: app
      image: local-only-app:v1
      imagePullPolicy: Never
EOF
```
`kind load docker-image` copies an image directly from the host's Docker
image store into every node's containerd store, side-stepping the need
for a registry entirely — this is *the* standard way to test a
locally-built image on `kind` without pushing it anywhere first.

**Lesson:** `kind` nodes are isolated containers with their own image
store, completely separate from the host's — this is one of the most
common "why can't my cluster see the image I just built" moments
specific to `kind` (and to a lesser extent, any container-based local
cluster tooling), and it produces an error message that looks nothing
like a registry problem because, mechanically, it isn't one.
