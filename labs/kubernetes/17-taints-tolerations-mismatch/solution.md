# Lab 17 — Solutions

## Challenge A — toleration present but doesn't actually match

**Check:**
```bash
kubectl --context kind-k8s17 describe node k8s17-control-plane | grep -A1 Taints
kubectl --context kind-k8s17 get deployment web -o jsonpath='{.spec.template.spec.tolerations}{"\n"}'
```

**Diagnosis:** the node's taint is `dedicated=gpu-workloads:NoSchedule`
but the Deployment's toleration has `effect: PreferNoSchedule`. A
toleration only cancels out a taint when `key`, `value` (or
`operator: Exists` with no value check), and `effect` all match — a
toleration for `PreferNoSchedule` does nothing against a `NoSchedule`
taint; they're treated as entirely different taints even though they
share the same key and value. This is the most common version of this
mistake: someone tolerates "a taint with this key" without checking that
the *effect* also lines up.

**Fix:**
```bash
kubectl --context kind-k8s17 patch deployment web --type=json -p '[
  {"op": "replace", "path": "/spec/template/spec/tolerations", "value": [
    {"key": "dedicated", "operator": "Equal", "value": "gpu-workloads", "effect": "NoSchedule"}
  ]}
]'
```

**Lesson:** "the pod has a toleration" is not the same question as "the
pod has *the right* toleration." Always diff the toleration's three
fields against the taint's three fields directly — `kubectl describe
node`'s `Taints:` line and the pod spec's `tolerations` list — rather
than eyeballing "yeah, that key looks familiar."

---

## Challenge B — `NoExecute` evicts, `NoSchedule` only blocks

**Check:**
```bash
kubectl --context kind-k8s17 get pods -l app=web -w
```

**Diagnosis:** pods that were `Running` before the taint landed
transition straight to `Terminating` shortly after the `NoExecute` taint
is applied, with no grace period beyond the pod's normal termination
grace period — unlike `NoSchedule`, which only ever affects the
scheduler's *next* placement decision and leaves anything already
running completely alone. `kubectl describe pod` around the eviction
shows an event referencing the taint directly, distinct from a
`FailedScheduling` event — this one is closer to a deletion than a
scheduling failure.

**Fix (same two options as Step 5, but the choice matters more here
because pods are actively being evicted, not just blocked):**
```bash
# remove the taint - pods reschedule back onto the node normally
kubectl --context kind-k8s17 taint nodes k8s17-control-plane hardware=degraded:NoExecute-

# or tolerate it, optionally only temporarily via tolerationSeconds
kubectl --context kind-k8s17 patch deployment web --type=json -p '[
  {"op": "add", "path": "/spec/template/spec/tolerations", "value": [
    {"key": "hardware", "operator": "Equal", "value": "degraded", "effect": "NoExecute", "tolerationSeconds": 60}
  ]}
]'
```

**Lesson:** `NoSchedule` and `NoExecute` are not two severities of the
same thing — they act on entirely different populations of pods.
`NoSchedule` is a placement-time filter (does nothing to pods already
running); `NoExecute` is a live eviction trigger (acts on running pods
immediately, and also blocks new scheduling). `tolerationSeconds` only
means anything on a `NoExecute` toleration — it says "let this pod keep
running on a now-tainted node for this many more seconds before evicting
it," useful for things like tolerating a brief node problem without an
immediate hard cutover. Applying it to a `NoSchedule` toleration is a
no-op, since `NoSchedule` was never going to evict anything to begin
with.
