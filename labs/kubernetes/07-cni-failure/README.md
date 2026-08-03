# Lab 7 — CNI Failure (Exhausted Pod CIDR, and a Broken CNI Config File)

## Objective
Exhaust a node's tiny pod IP range so new pods stay stuck in
`ContainerCreating` forever, diagnose the CNI-level error in
`kubectl describe pod`, then see a second, different CNI failure caused
by a broken config file on the node instead.

## Why this matters
"Pod stuck in `ContainerCreating`" is a huge bucket of unrelated failure
modes, and the CNI plugin failing to hand out an IP is one of the more
confusing ones because the pod's own spec is usually completely fine —
there's simply no IP address left to give it, or the plugin that assigns
IPs can't even start. The single most useful habit here is
`kubectl describe pod`'s Events section: the CNI error is almost always
sitting right there in plain text, but only if you know to scroll down
to it instead of re-checking the pod's image/command/volumes for the
tenth time.

## Prerequisites
- Docker installed and running
- `kind` and `kubectl`

Check first:
```bash
docker version
kind version 2>/dev/null || echo "kind not installed"
kubectl version --client 2>/dev/null || echo "kubectl not installed"
```

Cluster creation (this is what `setup.sh` runs for you — a deliberately
tiny pod subnet so exhaustion doesn't require hundreds of pods):
```bash
cat <<'EOF' > /tmp/lab-k8s07-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  podSubnet: "10.244.0.0/27"
EOF
kind create cluster --name k8s07 --config /tmp/lab-k8s07-config.yaml
```
(`/27` gives roughly 30 usable pod IPs on the single node — small enough
to exhaust with a handful of pods instead of hundreds, the same
"deliberately tiny" trick used for inodes in
[`labs/linux/11-disk-full-writes-fail`](../../linux/11-disk-full-writes-fail).)

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates the `k8s07` kind cluster with the tiny `/27` pod subnet
above, then scales a Deployment of plain `pause` containers up until new
pods stop getting IPs and stay `ContainerCreating`.

## Step 2 — Confirm the symptom
```bash
kubectl --context kind-k8s07 get pods -o wide
```
Some pods are `Running` with IPs assigned; the rest are stuck
`ContainerCreating`/`Pending` indefinitely.

## Step 3 — Read the actual CNI error
```bash
kubectl --context kind-k8s07 describe pod -l app=cidr-filler | grep -A5 Events | tail -30
```
Look for something like `failed to allocate for range 0: no IP addresses
available in range set` — this is the `host-local` IPAM plugin (used by
kindnetd) explicitly telling you the range is out of addresses, not a
vague timeout.

## Step 4 — Confirm the math
```bash
kubectl --context kind-k8s07 get nodes -o jsonpath='{.items[0].spec.podCIDR}{"\n"}'
kubectl --context kind-k8s07 get pods -o wide --no-headers | grep -v "<none>" | wc -l
```
Compare the node's actual `podCIDR` (a `/27` has 32 addresses total, a
handful reserved, ~29 usable) against how many pods already have an IP —
the arithmetic explains exactly why the next pod can't get one, no
guessing required.

## Step 5 — Fix it: free up IPs (the practical fix here) or grow the range
```bash
kubectl --context kind-k8s07 scale deployment cidr-filler --replicas=5
kubectl --context kind-k8s07 get pods -o wide -w
```
(Ctrl+C once the remaining pods get IPs and go `Running`.) In production,
the real fix for a genuinely exhausted pod CIDR is usually resizing
`--node-cidr-mask-size`/`podSubnet` at the cluster-network level (a bigger
change than this lab can safely make on a live cluster) — freeing up
unused pods is the equivalent of "stop leaking IPs" while that larger
change is planned.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — exhaustion returns immediately after "fixing" it:**
```bash
kubectl --context kind-k8s07 scale deployment cidr-filler --replicas=15
kubectl --context kind-k8s07 get pods -o wide
```
Scale back up past the range's real capacity and confirm the exact same
symptom returns. Using Step 4's arithmetic, calculate the maximum
`--replicas` value this specific `/27` can actually sustain alongside
kube-system's own pods (CoreDNS, kindnetd, etc. — they consume addresses
from the same range too) — don't guess, count what's actually already
allocated first.

**Challenge B — a broken CNI config file instead of range exhaustion:**
```bash
bash -c '
CTX=kind-k8s07
kubectl --context $CTX scale deployment cidr-filler --replicas=0
NODE=k8s07-control-plane
docker exec "$NODE" bash -c "mv /etc/cni/net.d/10-kindnet.conflist /etc/cni/net.d/10-kindnet.conflist.disabled"
kubectl --context $CTX run cni-broken-test --image=nginx --restart=Never
sleep 10
kubectl --context $CTX describe pod cni-broken-test | tail -20
'
```
Compare this pod's Events to Step 3's — different wording entirely
(look for something about not finding a CNI network/plugin at all, not
"no IP addresses available"). Figure out what this specific error
implies is missing versus what Step 3's implied, and fix it:
```bash
docker exec k8s07-control-plane bash -c "mv /etc/cni/net.d/10-kindnet.conflist.disabled /etc/cni/net.d/10-kindnet.conflist"
kubectl --context kind-k8s07 delete pod cni-broken-test
kubectl --context kind-k8s07 run cni-broken-test --image=nginx --restart=Never
kubectl --context kind-k8s07 wait --for=condition=Ready pod/cni-broken-test --timeout=60s
```

See `solution.md` only after you've formed your own diagnosis.
