# Lab 6 — Solutions

## Challenge A — QoS class decides who's evictable before usage does

**Check:**
```bash
kubectl --context kind-k8s06 get pod protected-pod -o jsonpath='{.status.qosClass}{"\n"}'
kubectl --context kind-k8s06 get pod canary-2 -o jsonpath='{.status.qosClass}{"\n"}' 2>/dev/null || echo "canary-2 gone"
kubectl --context kind-k8s06 get pods -o wide
```
`protected-pod` reports QoS class `Burstable` (it has requests set, even
though requests ≠ limits, which is enough to leave BestEffort).
`canary-2` (no requests/limits at all) is `BestEffort` and is the one
that's gone.

**Diagnosis:** kubelet's eviction manager ranks eviction candidates by
QoS class first, and only breaks ties within a class by resource usage:
`BestEffort` pods are evicted before any `Burstable` pod, which are
evicted before any `Guaranteed` pod, regardless of which one is
technically using more memory in absolute terms. `protected-pod` having
even a modest 64Mi request is enough to move it out of the first,
always-evicted-first tier — it's not that 64Mi/128Mi is "small enough to
be safe," it's that having *any* request at all changes its QoS
classification entirely.

**Fix:** giving a workload real `resources.requests`/`limits` is the
actual fix, not a lab command — it's the point being demonstrated. If you
need the cluster healthy again right now:
```bash
kubectl --context kind-k8s06 delete pod memory-hog-2 --grace-period=0 --force
```

**Lesson:** the cheapest, highest-leverage protection against your pod
being an eviction victim under resource pressure is setting
`resources.requests` (even a small, realistic value) — it's a QoS class
change, not just a scheduling hint, and QoS class is the first thing
kubelet's eviction manager checks, before it ever looks at how much of
the pressured resource any individual pod is actually using.

---

## Challenge B — DiskPressure evicts the same way, from a different signal

**Check:**
```bash
docker exec k8s06-control-plane df -h /var/lib/kubelet
kubectl --context kind-k8s06 describe node k8s06-control-plane | grep -A1 DiskPressure
kubectl --context kind-k8s06 get pods -o wide
```
`df -h` on the node shows usage climbing as the fill file grows.
`DiskPressure` flips to `True` once available space drops under
kubelet's default hard eviction threshold (`nodefs.available<10%` by
default), and the BestEffort `disk-canary` pod gets evicted, the same way
`nginx-canary` did for memory in the main lab.

**Diagnosis:** `MemoryPressure` and `DiskPressure` are two independent
node Conditions, driven by two independent eviction signals
(`memory.available` vs. `nodefs.available`/`imagefs.available`), but they
share the exact same eviction *mechanism* once triggered: rank candidates
by QoS class first, then by usage of whichever resource is under
pressure. The practical difference for an on-call engineer is what to
check first — `free`/`/proc/meminfo`-style signals for memory pressure,
versus `df`/disk usage for disk pressure — but `kubectl describe node`'s
Conditions section is the single command that tells you which one you're
actually dealing with, before you go looking at the wrong resource
entirely.

**Fix:**
```bash
docker exec k8s06-control-plane rm -rf /var/lib/lab6-fill
sleep 15
kubectl --context kind-k8s06 describe node k8s06-control-plane | grep -A1 DiskPressure
```

**Lesson:** don't assume "a pod disappeared under pressure" automatically
means memory — `kubectl describe node`'s Conditions section
(`MemoryPressure`, `DiskPressure`, `PIDPressure` all exist independently)
is the one place that tells you which resource kubelet actually reacted
to, and it takes exactly as long to check as guessing wrong does.
