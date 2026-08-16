# Lab 16 — Solutions

## Challenge A — the same aggressive timing, moved to readinessProbe

**Check:**
```bash
kubectl --context kind-k8s16 get pods -l app=slow-app -w
```
Watch `RESTARTS` and `READY` (the `n/n` column) separately for a minute.

**Diagnosis:** `RESTARTS` stays flat. `READY` flickers between `1/1` and
`0/1` as the pod repeatedly fails its now-too-tight readinessProbe. The
container is never killed — a failing readinessProbe only changes
whether the pod is counted as an endpoint a Service would route traffic
to; it never touches the container's lifecycle. `kubectl describe pod`
shows `Readiness probe failed` events with no accompanying
`Killing`/`Started` pair, which is the tell: compare that to Step 4's
Events, which had exactly that pair on every cycle.

**Fix:**
```bash
kubectl --context kind-k8s16 patch deployment slow-app --type=json -p '[
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/timeoutSeconds", "value": 5},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/periodSeconds", "value": 10},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/failureThreshold", "value": 3}
]'
```

**Lesson:** "probe failed" in the Events list is not enough information
on its own — you have to know which probe. A flapping `READY` column
with a flat `RESTARTS` column means Service traffic is being pulled away
from a pod that's still alive; a climbing `RESTARTS` column (Step 4) means
the container itself is being killed. Applying the fix for one to a
problem caused by the other does nothing — widening a livenessProbe
doesn't help a readinessProbe that's still too tight, and vice versa.

---

## Challenge B — slow startup vs. slow-under-load

**Check:**
```bash
kubectl --context kind-k8s16 describe pod -l app=slow-app | grep -A15 Events
```

**Diagnosis:** the Events cycle looks superficially like Step 4's again
(`Liveness probe failed` → `Killing` → `Started`), but the cause is
different: this container never finishes its 15s startup before
`initialDelaySeconds: 3` lets the livenessProbe start hitting it, so
every single attempt fails until the container is killed and restarted
from zero — it's stuck in a loop that never gets further than second 3
of a 15-second startup, versus Step 4's app, which *was* up and serving,
just occasionally slow to answer a given request. `kubectl logs
--previous` here would show the process being killed mid-`sleep`, before
it ever reached `serve_forever()` — no "handled some requests" period at
all, unlike Step 3.

**Fix (two valid approaches):**
```bash
# Option 1 - just push initialDelaySeconds past the known startup time
kubectl --context kind-k8s16 patch deployment slow-app --type=json -p '[
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds", "value": 20}
]'

# Option 2 - add a startupProbe and let it gate the livenessProbe
kubectl --context kind-k8s16 patch deployment slow-app --type=json -p '[
  {"op": "add", "path": "/spec/template/spec/containers/0/startupProbe", "value": {
    "httpGet": {"path": "/", "port": 8080},
    "periodSeconds": 5,
    "failureThreshold": 6
  }}
]'
```

**Lesson:** `initialDelaySeconds` is a single fixed guess about startup
time, made once, at Deployment-authoring time. A `startupProbe` checks
the real thing (has the app actually finished starting?) instead of
guessing a duration, and the livenessProbe simply doesn't run until the
startupProbe succeeds — which is why it's the better fix whenever
startup time varies (cold caches, slow dependency connections,
JIT/interpreter warmup) instead of being a known constant. Both fixes
"work" for this lab's fixed 15s delay, but only one of them survives
contact with a startup time that isn't always exactly 15s.
