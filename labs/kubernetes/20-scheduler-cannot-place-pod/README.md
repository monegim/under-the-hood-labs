# Lab 20 — Scheduler Cannot Place Pod

## Objective
Deploy a Pod whose spec is completely valid — no typo, no missing
field, nothing a linter would ever flag — and watch it sit `Pending`
forever anyway, because the number in `resources.requests.cpu` was
never checked against what any real node can actually provide. Then
learn that the exact same symptom, and often the exact same error
text, can come from at least three unrelated causes.

## Why this matters
A `Pending` Pod is one of the more disorienting things to debug if
you're used to thinking about failures in terms of the container
itself — there's no crash, no log output, nothing in the container at
all, because the container was never started. The scheduler simply
never found anywhere to put it, and it will keep retrying forever
without ever giving up or surfacing a louder alarm. `requests.cpu`
and `requests.memory` are values a developer writes once, based on a
guess or a copy-pasted template, and they can silently stop making
sense the moment the target environment changes — a value that fit
comfortably on a large production node can be larger than an entire
staging cluster's node. Nothing validates this at apply time; the API
server accepts the manifest just fine. The failure only shows up later,
as a Pod that never starts, and the reason lives entirely in
scheduler events most people don't think to check first.

## Prerequisites
- Docker installed and running
- `kind` and `kubectl`

Check first:
```bash
docker version
kind version 2>/dev/null || echo "kind not installed"
kubectl version --client 2>/dev/null || echo "kubectl not installed"
```

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates a single-node `k8s20` kind cluster and a Deployment named
`webapp` requesting `cpu: "20"` — 20 full CPU cores — an amount no
realistic single-node `kind` cluster (running inside Docker Desktop's
own resource-limited VM) is ever going to have.

## Step 2 — Confirm the incident
```bash
kubectl --context kind-k8s20 get pods -l app=webapp
```
`STATUS` says `Pending` and stays there — no `CrashLoopBackOff`, no
restarts, nothing. The container has never once been started.

## Step 3 — Read the actual reason
```bash
kubectl --context kind-k8s20 describe pod -l app=webapp
```
In the Events section:
```
Warning  FailedScheduling  ...  0/1 nodes are available: 1 Insufficient cpu. ...
```
Compare the request against what the node can actually offer:
```bash
NODE=$(kubectl --context kind-k8s20 get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl --context kind-k8s20 describe node "$NODE" | sed -n '/Allocatable:/,/System Info:/p'
```
Whatever your machine's `Allocatable.cpu` actually is — it's tied to
however many CPUs Docker Desktop's VM was given, not a fixed number —
it isn't 20.

## Step 4 — Fix it: request something the node can actually give
```bash
kubectl --context kind-k8s20 set resources deployment/webapp -c=webapp --requests=cpu=200m,memory=256Mi
```

## Step 5 — Verify
```bash
./check.sh
```
(The first pull of `nginx:1.27` on a brand-new cluster can take a
minute or two depending on your connection — `check.sh` just reports
the current state, so re-run it if the Pod is still `ContainerCreating`.)

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — same symptom, spec looks fine, completely different reason:**
```bash
./reset.sh
kubectl --context kind-k8s20 patch deployment webapp --type=json -p \
  '[{"op":"add","path":"/spec/template/spec/nodeSelector","value":{"disktype":"ssd"}},
    {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"200m"}]'
sleep 5
kubectl --context kind-k8s20 get pods -l app=webapp
kubectl --context kind-k8s20 describe pod -l app=webapp | grep -A3 "Events:"
```
Also `Pending`. Also a `FailedScheduling` event. But read the message
closely — is it the same wording as Step 3's, or does it say something
about affinity/selectors instead of any resource at all? Check what
label(s) your node actually has:
```bash
kubectl --context kind-k8s20 get nodes --show-labels
```
Work out why this Pod can never schedule no matter how small its
resource requests get, and why "just give it fewer resources" — the
Step 4 fix — does nothing here.

**Challenge B — the new Pod's own request is completely reasonable:**
```bash
./reset.sh
kubectl --context kind-k8s20 delete deployment webapp
cat <<'EOF' | kubectl --context kind-k8s20 apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: baseline
spec:
  replicas: 20
  selector:
    matchLabels:
      app: baseline
  template:
    metadata:
      labels:
        app: baseline
    spec:
      containers:
        - name: filler
          image: nginx:1.27
          resources:
            requests:
              cpu: "1"
              memory: "32Mi"
EOF
sleep 15
kubectl --context kind-k8s20 get pods -l app=baseline --no-headers | awk '{print $3}' | sort | uniq -c
kubectl --context kind-k8s20 describe node $(kubectl --context kind-k8s20 get nodes -o jsonpath='{.items[0].metadata.name}') | sed -n '/Allocated resources:/,/Events:/p'
```
`baseline` is a stand-in for "everything your team already deployed
before you got here" — 20 replicas each asking for a modest 1 CPU is
deliberately more than any single-node `kind` cluster's node actually
has, so some of them are `Pending` too, and the node's own Allocated
Resources are pinned near its ceiling regardless of your machine's
exact CPU count. Now add one more, ordinary-looking Pod on top:
```bash
cat <<'EOF' | kubectl --context kind-k8s20 apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      containers:
        - name: webapp
          image: nginx:1.27
          resources:
            requests:
              cpu: "200m"
              memory: "128Mi"
EOF
sleep 5
kubectl --context kind-k8s20 describe pod -l app=webapp | grep -A3 "Events:"
```
`webapp` asks for a fifth of a single CPU core — nothing unreasonable
about the number itself — and it still can't schedule, with the exact
same `Insufficient cpu` wording as Step 3. Explain why looking only at
`webapp`'s own resource block would send you looking in completely the
wrong place here, and what you'd actually need to check (and fix)
instead — hint: it isn't `webapp`'s manifest at all.

See `solution.md` only after you've formed your own diagnosis.
