# Lab 9 — API Server Unavailable

## Objective
Break the API server itself (not a workload, not a controller — the
component `kubectl` talks to) by feeding its static pod manifest a bad
flag, and learn what you can still check on a node when `kubectl` itself
stops working.

## Why this matters
Every other lab in this level assumes `kubectl` works and something else
is broken. This lab is different on purpose: when the API server is down,
`kubectl` — the tool you'd normally reach for to diagnose anything — is
now part of the outage, and returns some flavor of "connection refused"
or "unable to connect to the server" for absolutely everything, including
the commands you'd normally use to start debugging. Knowing what's still
available in that situation (the node is still a real machine — SSH/
`docker exec` still works, the container runtime is still running,
kubelet is still logging) is exactly the skill that separates "the
cluster is down, I'm stuck" from an actual diagnosis.

> **Design note:** this lab breaks the API server's **static pod
> manifest** (a bad flag causing it to crash-loop) rather than stopping
> the entire kind node container. That's deliberate: the whole point is
> to practice node-level diagnostics — `docker exec`, `crictl`, kubelet's
> own logs — which requires the node container itself to still be
> running. Challenge B does the more literal "stop the whole node" version
> so you can see the difference: sometimes you truly have nothing to
> check until the node itself comes back.

## Prerequisites
- Docker installed and running
- `kind` and `kubectl`

Check first:
```bash
docker version
kind version 2>/dev/null || echo "kind not installed"
kubectl version --client 2>/dev/null || echo "kubectl not installed"
```

Cluster creation (handled for you by `setup.sh`):
```bash
kind create cluster --name k8s09
```

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates the `k8s09` kind cluster, confirms `kubectl` works
normally, then edits `/etc/kubernetes/manifests/kube-apiserver.yaml` on
the control-plane node so `--etcd-servers` points at the wrong port
(`https://127.0.0.1:23790` instead of `2379`). kubelet picks up the
manifest change automatically and restarts the API server container,
which now can't reach etcd at all and crash-loops.

## Step 2 — Confirm the symptom
```bash
kubectl --context kind-k8s09 get nodes
```
This fails — something like `The connection to the server
127.0.0.1:<port> was refused` or a timeout. Every other `kubectl` command
against this cluster fails the same way right now.

## Step 3 — Diagnose without kubectl: node-level tools only
```bash
NODE=k8s09-control-plane
docker ps --filter "name=${NODE}"
```
The node **container** itself is still `Up` — this is not the node being
down, it's one static pod on it being broken. Get inside it:
```bash
docker exec -it "${NODE}" bash
```
From inside the node, `kubectl` still won't work (it's still trying to
reach the same broken API server), but the container runtime and
kubelet are node-local and don't depend on the API server at all:
```bash
crictl ps -a | grep kube-apiserver
```
This shows the `kube-apiserver` container in a restart loop (`Exited`,
repeatedly, recent `CREATED`/`STARTED` timestamps). Get its logs
directly from the runtime — no apiserver required for this:
```bash
crictl logs "$(crictl ps -a --name kube-apiserver -q | head -1)" 2>&1 | tail -30
```
Look for a connection error to etcd on the wrong port — this confirms
the API server's own logs are still fully readable at the node level,
even though nothing above the node can reach the API server at all.

## Step 4 — Check kubelet itself and the manifest
```bash
journalctl -u kubelet --no-pager | tail -30
cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep etcd-servers
```
kubelet's own logs (a systemd-managed service on the node, independent of
the API server) show it repeatedly trying and failing to get the static
pod healthy. The manifest itself has the bad `--etcd-servers` value in
plain text — this is the smoking gun, found entirely without `kubectl`.

## Step 5 — Fix it
Still inside the node container:
```bash
sed -i 's#https://127.0.0.1:23790#https://127.0.0.1:2379#' /etc/kubernetes/manifests/kube-apiserver.yaml
exit
```
kubelet detects the manifest change automatically and restarts the API
server. From your host:
```bash
sleep 15
kubectl --context kind-k8s09 get nodes
```
This should now succeed again.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a different flag, a different crash reason:**
```bash
bash -c '
NODE=k8s09-control-plane
docker exec "$NODE" bash -c "
  sed -i \"s#--etcd-cafile=[^ ]*#--etcd-cafile=/etc/kubernetes/pki/does-not-exist.crt#\" /etc/kubernetes/manifests/kube-apiserver.yaml
"
sleep 15
docker exec "$NODE" bash -c "crictl logs \$(crictl ps -a --name kube-apiserver -q | head -1) 2>&1 | tail -20"
'
```
Compare this crash reason to Step 3's. Same overall symptom
(`kubectl` unreachable, apiserver crash-looping), but the log text is
different — figure out exactly what's different about *why* it's
crashing this time, and fix it the same way (find and correct the bad
line in the manifest, node-side).

**Challenge B — the whole node is down, not just the API server:**
```bash
docker stop k8s09-control-plane
docker exec -it k8s09-control-plane bash    # this itself now fails
kubectl --context kind-k8s09 get nodes
```
Neither `docker exec` nor `kubectl` works now — there is genuinely
nothing to inspect until the container itself comes back (unlike Steps
3-4, where the node was fully inspectable the whole time). Confirm this
is the actual difference, then bring it back:
```bash
docker start k8s09-control-plane
sleep 20
kubectl --context kind-k8s09 get nodes
```
What real-world incident does *this* version map to, that Steps 1-5
don't?

See `solution.md` only after you've formed your own diagnosis.
