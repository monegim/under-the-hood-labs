# Lab 19 — Image Pull Failure

## Objective
Reproduce the single most common reason a Pod never starts —
`ImagePullBackOff` from a typo'd tag — then learn to read the *exact*
wording of the pull error to tell three structurally different causes
apart, because "fix the image" means something completely different
depending on which one you're looking at.

## Why this matters
A Pod stuck in `ImagePullBackOff`/`ErrImagePull` looks identical at a
glance no matter *why* it's failing — `kubectl get pods` just shows the
same status string regardless of cause. But "the image doesn't exist,"
"the registry itself isn't reachable," and "the image was never made
available to this node" are three completely different problems with
three completely different fixes, and `kubectl describe pod`'s Events
section spells out which one you're looking at in the exact error text —
if you read past the status column instead of stopping at it.

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
This creates a single-node `k8s19` kind cluster and a Deployment named
`webapp` referencing `nginx:1.99.99-nonexistent-tag` — a tag that has
never existed on Docker Hub.

## Step 2 — Confirm the incident
```bash
kubectl --context kind-k8s19 get pods -l app=webapp
```
`STATUS` cycles between `ErrImagePull` and `ImagePullBackOff` — Kubernetes
keeps retrying with exponential backoff, and it will keep failing forever
without help.

## Step 3 — Read the actual error, not just the status
```bash
kubectl --context kind-k8s19 describe pod -l app=webapp
```
In the Events section:
```
Failed to pull image "nginx:1.99.99-nonexistent-tag": ... failed to resolve reference
"docker.io/library/nginx:1.99.99-nonexistent-tag": ...: not found
```
"not found" is the key phrase — the registry (`docker.io`) was reached
just fine; it's the specific tag that doesn't exist there.

## Step 4 — Fix it: correct the tag
```bash
kubectl --context kind-k8s19 set image deployment/webapp nginx=nginx:1.27
```

## Step 5 — Verify
```bash
./check.sh
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the registry itself is the problem, not the tag:**
```bash
./reset.sh
kubectl --context kind-k8s19 set image deployment/webapp nginx=registry.internal.example.corp/webapp:v1
sleep 10
kubectl --context kind-k8s19 describe pod -l app=webapp | grep -A3 "Failed to pull"
```
This produces a *differently worded* failure than Step 3's — no "not
found" anywhere. Read it closely: does it say anything about the image
existing or not existing at all? What is it actually complaining about,
and what does that tell you about how far the request even got before
failing? (The exact wording of a DNS/connection failure varies some by
network setup — the categorical difference from Step 3's "not found" is
what to focus on, not the precise phrasing.)

**Challenge B — `kubectl describe` shows a completely different reason, no registry involved at all:**
```bash
./reset.sh
kubectl --context kind-k8s19 delete deployment webapp
mkdir -p /tmp/lab19-local-image && cat > /tmp/lab19-local-image/Dockerfile <<'EOF'
FROM busybox:latest
CMD ["sh", "-c", "while true; do echo alive; sleep 30; done"]
EOF
docker build -t local-only-app:v1 /tmp/lab19-local-image
cat <<EOF | kubectl --context kind-k8s19 apply -f -
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
sleep 5
kubectl --context kind-k8s19 get pod local-only-app
kubectl --context kind-k8s19 describe pod local-only-app | grep -A2 "Events:"
```
`local-only-app:v1` was just built successfully on your own machine —
`docker images | grep local-only-app` proves it exists — and the Pod
still can't start. The reason named in the Events section isn't about
pulling at all. What does `imagePullPolicy: Never` actually promise
Kubernetes, and why does a perfectly real, freshly-built image fail to
satisfy it here specifically (hint: what does "your own machine" actually
mean once `kind` is involved)?

See `solution.md` only after you've formed your own diagnosis.
