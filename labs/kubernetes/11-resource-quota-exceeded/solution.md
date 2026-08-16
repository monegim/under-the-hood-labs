# Lab 11 — Solutions

## Challenge A — quota rejection happens on the ReplicaSet, not the Deployment

**Check:**
```bash
kubectl --context kind-k8s11 -n team-a get deployment app-4
kubectl --context kind-k8s11 -n team-a get replicaset -l app=app-4
kubectl --context kind-k8s11 -n team-a describe replicaset -l app=app-4
```
`get deployment app-4` shows something like `1/5` Ready, stuck. `describe
replicaset`'s Events show `FailedCreate` with the same `exceeded quota:
compute-quota, requested: ...` message from Step 2 — just repeated once
per Pod the ReplicaSet controller tried and failed to create.

**Diagnosis:** a Deployment never creates Pods directly — it creates/scales
a ReplicaSet, and the ReplicaSet controller is what actually calls "create
Pod" against the API server. Quota enforcement happens at that Pod-create
call, several layers below where you issued `kubectl scale`. That command
succeeded because scaling a Deployment just means updating
`spec.replicas`, which quota doesn't touch at all — the rejection happens
later, asynchronously, inside a controller loop you never directly
interacted with. This is exactly why `kubectl apply`/`scale` reporting
success proves nothing about whether the workload actually reached its
desired state.

**Fix:** same as Step 5 — either free capacity elsewhere in `team-a`, or
raise `compute-quota`'s `hard` values, then the stalled ReplicaSet will
succeed on its own without you doing anything else:
```bash
kubectl --context kind-k8s11 -n team-a patch resourcequota compute-quota --type=json -p='[
  {"op":"replace","path":"/spec/hard/requests.cpu","value":"2"},
  {"op":"replace","path":"/spec/hard/requests.memory","value":"2000Mi"}
]'
kubectl --context kind-k8s11 -n team-a get deployment app-4
```

**Lesson:** when a Deployment is stuck below its desired replica count
with no visible error on the Deployment object itself, check the
ReplicaSet's Events next, not the Deployment's. Quota, PodSecurity, and
admission webhook rejections all happen at Pod-create time, which for
anything managed by a Deployment means the ReplicaSet is the object that
actually sees (and reports) the failure.

---

## Challenge B — quota demands explicit requests/limits, rejecting the Pod outright

**Check:**
```bash
kubectl --context kind-k8s11 -n team-a run app-5 --image=nginx --restart=Never
```
The error is something like:
```
Error from server (Forbidden): pods "app-5" is forbidden: failed quota: compute-quota: must specify limits.cpu,limits.memory,requests.cpu,requests.memory
```
No `used`/`hard` comparison at all — just a list of fields that are
missing.

**Diagnosis:** once a `ResourceQuota` in a namespace covers a compute
resource (`requests.cpu`, `limits.memory`, etc.), the quota admission
plugin requires every new Pod's containers to explicitly declare that
resource — it will not assume a default and it will not "count as zero."
`kubectl run` with no `--overrides` creates a Pod with no
`resources` block at all, which the plugin can't account against the
quota, so it refuses the Pod before it even gets to comparing numbers.
This is a completely different rejection path from Step 2/Challenge A:
those failed because a specific number was too high; this fails because
no number was given at all, and it would fail identically even if the
namespace's quota had unlimited headroom left.

**Fix:**
```bash
kubectl --context kind-k8s11 -n team-a run app-5 --image=nginx --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"app-5","image":"nginx","resources":{"requests":{"cpu":"50m","memory":"50Mi"},"limits":{"cpu":"100m","memory":"100Mi"}}}]}}'
```

**Lesson:** a namespace with any compute `ResourceQuota` implicitly
requires *every* Pod in it to set `requests`/`limits` for the resources
that quota covers — this is enforced even for tiny, obviously-harmless
Pods, and even when there's plenty of quota headroom. A `LimitRange`
object can set namespace-wide defaults so bare Pods don't need to specify
this manually every time; without one, "must specify limits.cpu..." is
the price of not having defaults configured.
