# Lab 7 — Solutions

## Challenge A — computing real sustainable capacity

**Check:**
```bash
kubectl --context kind-k8s07 get nodes -o jsonpath='{.items[0].spec.podCIDR}{"\n"}'
kubectl --context kind-k8s07 get pods -A -o wide --no-headers | grep -vc "<none>"
```
A `/27` has 32 total addresses; `host-local` IPAM reserves the network
and broadcast addresses (2), leaving 30 usable. Every `Running` pod
cluster-wide — including `kube-system`'s CoreDNS replicas and `kindnetd`
itself, which all consume addresses from the same range — counts against
that 30, not just your own Deployment's replicas.

**Diagnosis:** the failure in Challenge A isn't a new bug, it's the exact
same arithmetic from Step 4 applied again after temporarily freeing
capacity — `cidr-filler`'s sustainable replica count is `30 minus
whatever kube-system and any other pods are already using`, not 30
outright. Scaling back up past that recomputed ceiling reproduces the
identical `no IP addresses available in range set` error for the
identical reason.

**Fix:** count what's already running first, then scale to fit:
```bash
ALREADY_RUNNING=$(kubectl --context kind-k8s07 get pods -A -o wide --no-headers | grep -vc "<none>")
SAFE_REPLICAS=$(( (30 - ALREADY_RUNNING > 0 ? 30 - ALREADY_RUNNING : 0) ))
kubectl --context kind-k8s07 scale deployment cidr-filler --replicas="$SAFE_REPLICAS"
```

**Lesson:** a tiny pod CIDR isn't a one-time obstacle you fix and move
past — it's a hard ceiling on the entire node's total pod count,
including system pods you didn't create. Any capacity-planning
conversation about pod density has to account for every pod on the node,
not just the workload you're actively scaling.

---

## Challenge B — missing CNI config vs. exhausted CNI range

**Check:**
```bash
kubectl --context kind-k8s07 describe pod cni-broken-test | grep -A10 Events
```
The error here is something like `network plugin is not ready: cni
config uninitialized` or `failed to find plugin "..." in path`, not
anything about IP ranges being out of addresses.

**Diagnosis:** `host-local`'s "no IP addresses available" (Step 3) is a
failure *inside* a working CNI setup — the plugin runs fine, it just has
nothing left to allocate. Renaming `/etc/cni/net.d/10-kindnet.conflist`
away removes kubelet's ability to find *any* CNI configuration at all on
that node — kubelet watches `/etc/cni/net.d/` for a valid config file
before it will even attempt to set up networking for a new pod, and with
none present, every new pod on that node fails identically regardless of
how much of the pod CIDR is actually free. This is a strictly worse
failure than range exhaustion: exhaustion only blocks pods once the range
is full; a missing CNI config blocks every single new pod on the node
immediately, from the first one.

**Fix:**
```bash
docker exec k8s07-control-plane bash -c "mv /etc/cni/net.d/10-kindnet.conflist.disabled /etc/cni/net.d/10-kindnet.conflist"
kubectl --context kind-k8s07 delete pod cni-broken-test
kubectl --context kind-k8s07 run cni-broken-test --image=nginx --restart=Never
kubectl --context kind-k8s07 wait --for=condition=Ready pod/cni-broken-test --timeout=60s
```

**Lesson:** "no IP addresses available in range set" and "network plugin
is not ready"/"failed to find plugin" are both CNI-layer failures but
point at completely different places to look — one is a capacity problem
inside a working CNI plugin, the other means the CNI plugin's
configuration is missing or invalid on that node entirely
(`/etc/cni/net.d/` is the first place to check when it's the latter). Read
the exact event text before assuming "CNI problem" means "need more IP
addresses."
