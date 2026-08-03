# Lab 3 — etcd Full (Quota Exceeded)

## Objective
Drive etcd into its `NOSPACE` alarm state by exceeding its
`--quota-backend-bytes` limit, watch writes cluster-wide start failing
with `etcdserver: mvcc: database space exceeded`, then recover with the
real fix: compact, defragment, disarm.

## Why this matters
etcd enforces a hard backend storage quota (default 2GiB) specifically so
a runaway workload (a controller that never garbage-collects objects, a
CI system that leaves thousands of completed Jobs behind, a webhook that
leaks Secrets) can't grow etcd's database file without bound and take the
whole cluster down uncontrolled. But when the quota **is** hit, the
failure mode is confusing if you've never seen it: `kubectl apply`/`create`
start failing with a cryptic etcd-internals error message that has nothing
to do with your actual manifest, while `kubectl get`/`describe` keep
working completely normally (etcd still serves reads fine under the
alarm — only writes are blocked). Cluster-wide "writes fail, reads don't"
is a distinctive enough signature that it's worth recognizing on sight
instead of re-reading your YAML for the tenth time.

> **Honesty note:** kind runs a single-node etcd with no realistic way to
> organically accumulate 2GiB of cluster state in a lab session. This lab
> simulates the alarm condition directly by **lowering**
> `--quota-backend-bytes` on the etcd static pod to something small enough
> to exceed on purpose (documented, supported etcd behavior — this is not
> a hack, just a much lower ceiling than production would use). Treat the
> exact numbers here as a simulation of the real failure, not a literal
> reproduction of a 2GiB production incident.

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
kind create cluster --name k8s03
```

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates the `k8s03` kind cluster, then:
- edits `/etc/kubernetes/manifests/etcd.yaml` on the control-plane node
  container to add `--quota-backend-bytes=16777216` (16MiB — kubelet
  picks up static pod manifest changes automatically and restarts etcd)
- waits for etcd and the API server to come back healthy
- creates ConfigMaps containing ~256KB of random data each, in a loop,
  until etcd's `NOSPACE` alarm actually triggers (checking
  `etcdctl alarm list` between batches)

All `etcdctl` commands run via `kubectl exec` into the `etcd-<node>`
static pod, using the certs already mounted there — no extra binaries
need installing anywhere.

## Step 2 — Confirm the symptom: writes fail, reads don't
```bash
kubectl --context kind-k8s03 get nodes
kubectl --context kind-k8s03 create configmap post-alarm-test --from-literal=foo=bar
```
`get nodes` succeeds normally. `create configmap` fails with something
like `Internal error occurred: etcdserver: mvcc: database space exceeded`
— note this is a **500-level API server error about etcd internals**, not
a validation error about your ConfigMap.

## Step 3 — Confirm it's the quota, not something else
```bash
CP=k8s03-control-plane
ETCD_POD=$(kubectl --context kind-k8s03 -n kube-system get pods -l component=etcd -o jsonpath='{.items[0].metadata.name}')
kubectl --context kind-k8s03 -n kube-system exec "$ETCD_POD" -- \
  etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    endpoint status --write-out=table
kubectl --context kind-k8s03 -n kube-system exec "$ETCD_POD" -- \
  etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    alarm list
```
`endpoint status` shows `DB SIZE` at (or past) the 16MiB quota you set.
`alarm list` shows `memberID:... alarm:NOSPACE` — this is etcd explicitly
telling you why it's rejecting writes, not a guess.

> If `kubectl exec` into the etcd pod itself starts failing or hanging
> (etcd's liveness probe can flap under the alarm and kubelet may restart
> its container), fall back to node-level access exactly as in
> [Lab 9](../09-api-server-unavailable):
> `docker exec -it k8s03-control-plane crictl exec <etcd-container-id> etcdctl ...`

## Step 4 — Fix it: compact, defrag, disarm
```bash
ETCD_POD=$(kubectl --context kind-k8s03 -n kube-system get pods -l component=etcd -o jsonpath='{.items[0].metadata.name}')
ETCDCTL="kubectl --context kind-k8s03 -n kube-system exec $ETCD_POD -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"

# 1. Delete the junk ConfigMaps this lab created (reduces logical data first)
kubectl --context kind-k8s03 delete configmap -l lab=etcd-full --all-namespaces 2>/dev/null || \
  kubectl --context kind-k8s03 get configmap -o name | grep etcdfull- | xargs -r kubectl --context kind-k8s03 delete

# 2. Compact to the current revision (etcd keeps old revisions around until told to drop them)
REV=$($ETCDCTL endpoint status --write-out=json | grep -o '"revision":[0-9]*' | head -1 | cut -d: -f2)
$ETCDCTL compact "$REV"

# 3. Defragment to actually reclaim disk space from the compacted revisions
$ETCDCTL defrag

# 4. Disarm the alarm - this is what actually lets writes resume
$ETCDCTL alarm disarm
$ETCDCTL alarm list
```
Re-run the Step 2 `kubectl create configmap` command — it should now
succeed.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — writes fail but `alarm list` is empty:**
```bash
bash -c '
ETCD_POD=$(kubectl --context kind-k8s03 -n kube-system get pods -l component=etcd -o jsonpath="{.items[0].metadata.name}")
i=0
while [ $i -lt 40 ]; do
  kubectl --context kind-k8s03 create configmap etcdfull2-$i --from-literal=data="$(head -c 262144 /dev/urandom | base64 | tr -d \"\n\")" >/dev/null 2>&1
  i=$((i+1))
done
kubectl --context kind-k8s03 create configmap post-test-2 --from-literal=foo=bar
'
```
If this succeeds instead of failing, you have not yet reproduced the
challenge — the point is to notice the *approach* to the quota
(`endpoint status` DB SIZE climbing toward, but not yet over, the quota)
looks identical to Step 3 right up until the alarm actually fires. Find
the exact command that tells you "not there yet" vs. "already there,"
and explain why a single write can succeed on one attempt and fail on the
very next one with no visible change in your own commands.

**Challenge B — compact alone doesn't fix it:**
```bash
ETCD_POD=$(kubectl --context kind-k8s03 -n kube-system get pods -l component=etcd -o jsonpath='{.items[0].metadata.name}')
ETCDCTL="kubectl --context kind-k8s03 -n kube-system exec $ETCD_POD -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"
REV=$($ETCDCTL endpoint status --write-out=json | grep -o '"revision":[0-9]*' | head -1 | cut -d: -f2)
$ETCDCTL compact "$REV"
kubectl --context kind-k8s03 create configmap post-compact-test --from-literal=foo=bar
```
This still fails, even though you just compacted. Check `endpoint status`
(`DB SIZE` specifically) before and after the compact command, and figure
out what compact actually did vs. what it didn't do — and which single
extra command (from Step 4) is the one that actually shrinks `DB SIZE` on
disk.

See `solution.md` only after you've formed your own diagnosis.
