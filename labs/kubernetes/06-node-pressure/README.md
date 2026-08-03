# Lab 6 — Node Under Memory Pressure

## Objective
Push a kind node into real `MemoryPressure`, watch kubelet's eviction
manager actually evict a BestEffort pod to relieve it, then read
`kubectl describe node`'s Conditions section and events the way you would
during a real capacity incident.

## Why this matters
"The pod is gone and I don't know why" is a much scarier ticket than
"the pod crashed" — a crash leaves a `CrashLoopBackOff` and a
`kubectl logs --previous` trail; an eviction just removes the pod, and if
you don't already know to check `kubectl describe node`'s Conditions and
`kubectl get events`, it can look like the pod (or Kubernetes itself)
vanished for no reason. Pods without memory limits are exactly what makes
a node vulnerable to this in the first place — kubelet's eviction manager
exists specifically to sacrifice something before the kernel OOM-killer
has to choose blindly, and knowing how to read *why* it chose what it
chose is core on-call skill.

> **Safety note:** this lab has the memory-hog pod target a percentage of
> the kind **node container's** own memory (computed dynamically from
> `/proc/meminfo` inside the node container by `setup.sh`), not a fixed
> hardcoded amount — because a kind node is a Docker container sharing
> your host's kernel with no memory limit by default, "the node" here
> really does mean your machine's memory. `setup.sh` prints the computed
> target before running anything and keeps it modest (aims to trigger
> kubelet's eviction thresholds without threatening the host); if you're
> on a memory-constrained machine, review `setup.sh` before running it and
> consider lowering `MEM_PERCENT`.

## Prerequisites
- Docker installed and running
- `kind` and `kubectl`

Check first:
```bash
docker version
kind version 2>/dev/null || echo "kind not installed"
kubectl version --client 2>/dev/null || echo "kubectl not installed"
free -h   # know your own headroom before running this lab
```

Cluster creation (handled for you by `setup.sh`):
```bash
kind create cluster --name k8s06
```

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates the `k8s06` kind cluster, deploys a normal BestEffort
`nginx` pod (no resource requests/limits — deliberately, since
BestEffort pods are always evicted first) as a "canary" workload, then
deploys a memory-hog pod (also BestEffort, using `stress-ng --vm-bytes`)
sized at ~80% of the node container's total memory, and waits to see
kubelet react.

## Step 2 — Watch memory pressure develop
```bash
kubectl --context kind-k8s06 describe node k8s06-control-plane | grep -A1 MemoryPressure
kubectl --context kind-k8s06 get events --sort-by=.lastTimestamp | tail -20
```
Once the hog pod's allocation crosses kubelet's eviction threshold
(`memory.available` below the default hard threshold, typically 100Mi),
the `MemoryPressure` Condition flips to `True`, and events show kubelet
evicting something.

## Step 3 — See what got evicted, and why
```bash
kubectl --context kind-k8s06 get pods -o wide
kubectl --context kind-k8s06 get pod nginx-canary -o jsonpath='{.status.reason}{"\n"}'
```
The canary `nginx` pod (BestEffort, no requests/limits, nothing
"protecting" it) is the one that got evicted — not the memory hog
itself necessarily, and that's the point of Step 4.

## Step 4 — Understand why the hog isn't always the one evicted
```bash
kubectl --context kind-k8s06 describe node k8s06-control-plane | grep -A10 "Allocated resources"
```
Eviction picks victims by **QoS class first, resource usage second**:
all BestEffort pods are candidates before any Burstable/Guaranteed pod is
touched, and among BestEffort pods, kubelet evicts whichever is using the
most of the pressured resource — which is usually the hog itself, but
not guaranteed if multiple BestEffort pods exist. This step's grep is
about seeing that QoS class, not raw memory usage, is the first cut.

## Step 5 — Fix it: stop the hog
```bash
kubectl --context kind-k8s06 delete pod memory-hog --grace-period=0 --force
sleep 15
kubectl --context kind-k8s06 describe node k8s06-control-plane | grep -A1 MemoryPressure
```
`MemoryPressure` should return to `False` shortly after the hog is gone.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a pod with resource requests survives, another BestEffort pod doesn't:**
```bash
bash -c '
CTX=kind-k8s06
kubectl --context $CTX run protected-pod --image=nginx --restart=Never \
  --overrides="{\"spec\":{\"containers\":[{\"name\":\"protected-pod\",\"image\":\"nginx\",\"resources\":{\"requests\":{\"memory\":\"64Mi\"},\"limits\":{\"memory\":\"128Mi\"}}}]}}"
kubectl --context $CTX run canary-2 --image=nginx --restart=Never
kubectl --context $CTX apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: memory-hog-2
spec:
  containers:
    - name: stress
      image: polinux/stress-ng
      args: ["--vm", "1", "--vm-bytes", "80%", "--vm-hang", "0"]
EOF
sleep 30
kubectl --context $CTX get pods -o wide
'
```
Compare which pod(s) got evicted here to Step 3. Explain, using QoS class
(`kubectl get pod <name> -o jsonpath='{.status.qosClass}'`), why
`protected-pod` survives even though the node is still under exactly the
same memory pressure.

**Challenge B — disk pressure instead of memory pressure:**
```bash
bash -c '
CTX=kind-k8s06
NODE=k8s06-control-plane
kubectl --context $CTX run disk-canary --image=nginx --restart=Never
# Fill toward, but capped well under, whatever headroom the node container
# actually has right now - check first, never assume:
docker exec "$NODE" df -h /var/lib/kubelet
docker exec "$NODE" mkdir -p /var/lib/lab6-fill
docker exec "$NODE" dd if=/dev/zero of=/var/lib/lab6-fill/bigfile bs=1M count=1024 status=progress || true
sleep 20
kubectl --context $CTX describe node "$NODE" | grep -A1 DiskPressure
kubectl --context $CTX get pods -o wide
'
```
Check `docker exec k8s06-control-plane df -h /var/lib/kubelet` **before**
running this — if the node container is reporting less than a few GB
free (it shares your host's real disk), lower `count=1024` (MB) to
something clearly safe for your machine first. Diagnose the
`DiskPressure` Condition and eviction the same way as Steps 2-4, then
clean up with
`docker exec k8s06-control-plane rm -rf /var/lib/lab6-fill` — what
differs about which pods get evicted, and what a real "node disk full"
incident looks like versus memory pressure?

See `solution.md` only after you've formed your own diagnosis.
