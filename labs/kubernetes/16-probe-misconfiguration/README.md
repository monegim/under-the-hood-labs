# Lab 16 — Probe Misconfiguration (Liveness Probe Too Aggressive for the App)

## Objective
Deploy an otherwise-healthy app that's just occasionally slow to respond,
pair it with a livenessProbe whose timing was copy-pasted from something
much faster, and watch kubelet kill and restart a perfectly working
container over and over. Learn to tell this apart from a real crash, and
to stop conflating what a failing readinessProbe does versus what a
failing livenessProbe does.

## Why this matters
A container stuck in `CrashLoopBackOff` reads as "the app is broken," so
the instinct is to go straight to the app's logs looking for a stack
trace. That instinct fails completely here: the app never errors, never
panics, never even logs anything unusual — it's just slow sometimes,
which is normal for a real service under real load. The actual cause is
entirely in the Deployment's probe timing, and the only way to see it is
`kubectl describe pod`'s Events section showing kubelet's own
`Killing`/`Started` cycle, cross-referenced against how long the app
actually takes to respond. The second, easily-conflated mistake this lab
targets: a failing **readiness** probe just pulls the pod out of a
Service's endpoints (traffic stops routing to it, nothing is killed); a
failing **liveness** probe kills the container outright. Mixing these up
either overreacts to a slow response (killing a container that was about
to recover on its own) or underreacts to one (leaving a genuinely wedged
container in the traffic rotation).

## Prerequisites
- Docker installed and running
- `kind` and `kubectl`

Check first:
```bash
docker version
kind version 2>/dev/null || echo "kind not installed"
kubectl version --client 2>/dev/null || echo "kubectl not installed"
```

Cluster creation (this is what `setup.sh` runs for you):
```bash
kind create cluster --name k8s16
```

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates the `k8s16` kind cluster and deploys `slow-app`, a
stdlib-only Python HTTP server where about half of all requests take
~2.5s to respond (the other half respond instantly — this is what "slow
under load" actually looks like, not uniformly slow). It ships with a
sane `readinessProbe` (`timeoutSeconds: 3`, `failureThreshold: 3`) and a
deliberately too-tight `livenessProbe` (`timeoutSeconds: 1`,
`periodSeconds: 5`, `failureThreshold: 1`).

## Step 2 — Confirm the symptom
```bash
kubectl --context kind-k8s16 get pods -l app=slow-app
```
`RESTARTS` climbs steadily even though nothing about the Deployment
itself looks wrong. Watch it happen live:
```bash
kubectl --context kind-k8s16 get pods -l app=slow-app -w
```

## Step 3 — Rule out an actual crash
```bash
POD=$(kubectl --context kind-k8s16 get pods -l app=slow-app -o jsonpath='{.items[0].metadata.name}')
kubectl --context kind-k8s16 logs "$POD" --previous
```
The previous container's logs end cleanly — no traceback, no error, no
OOM, nothing. It was serving requests right up until something external
killed it. That "something external" is the next step.

## Step 4 — Read the Events, then compare to the probe config
```bash
kubectl --context kind-k8s16 describe pod -l app=slow-app | grep -A15 Events
```
Look for a repeating cycle: `Liveness probe failed` followed by `Killing`
followed by `Started` — this is kubelet, not the app, ending the
container's life. Now pull the actual probe timing and compare it to
what you already know about the app's latency:
```bash
kubectl --context kind-k8s16 get deployment slow-app \
  -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}{"\n"}'
```
`timeoutSeconds: 1` against an app that regularly takes 2.5s to answer —
the probe was never going to pass consistently, no matter how healthy the
app is.

## Step 5 — Fix it: widen the livenessProbe timing
```bash
kubectl --context kind-k8s16 patch deployment slow-app --type=json -p '[
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/timeoutSeconds", "value": 5},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/periodSeconds", "value": 10},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/failureThreshold", "value": 3}
]'
kubectl --context kind-k8s16 rollout status deployment/slow-app
```
Now a single slow response can't trigger a kill on its own — the probe
has to see 3 consecutive failures with a 5s timeout each, which the app's
occasional 2.5s response never actually causes.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — same aggressive timing, but on the readinessProbe instead:**
```bash
kubectl --context kind-k8s16 patch deployment slow-app --type=json -p '[
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/timeoutSeconds", "value": 1},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/failureThreshold", "value": 1},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/timeoutSeconds", "value": 5},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/failureThreshold", "value": 3}
]'
kubectl --context kind-k8s16 get pods -l app=slow-app -w
```
Watch the `RESTARTS` count and the `READY` column separately for a
minute. Figure out which one moves now and which one stays put — that
difference *is* the readiness-vs-liveness distinction this lab is about.
Check `kubectl describe pod` events again: same "probe failed" language,
completely different consequence. Fix it by giving the readinessProbe
timing that fits the app's actual latency (mirror Step 5's values).

**Challenge B — a slow-starting app instead of a slow-under-load one:**
```bash
kubectl --context kind-k8s16 set env deployment/slow-app STARTUP_DELAY=15
kubectl --context kind-k8s16 patch deployment slow-app --type=json -p '[
  {"op": "replace", "path": "/spec/template/spec/containers/0/command", "value": ["python3", "-c", "import os,time; time.sleep(int(os.environ.get(\"STARTUP_DELAY\",0))); exec(open(\"/scripts/app.py\").read())"]}
]'
kubectl --context kind-k8s16 rollout status deployment/slow-app --timeout=30s || true
kubectl --context kind-k8s16 describe pod -l app=slow-app | grep -A15 Events
```
This app now takes 15s just to start listening at all — a one-time cold
start, not per-request load — but the livenessProbe's
`initialDelaySeconds: 3` from Step 5 has no idea about that. Compare this
failure's Events output to Challenge A's: is this the same "occasionally
too slow to answer" problem, or a different one entirely (the container
never gets a chance to finish starting before it's killed)? Fix it two
different ways and think about which one you'd actually want in
production:
1. Just raise `initialDelaySeconds` on the livenessProbe past the
   startup time.
2. Add a `startupProbe` with its own generous `failureThreshold` /
   `periodSeconds`, so the livenessProbe only starts being evaluated
   once startup genuinely finishes — the fix `initialDelaySeconds` can't
   express cleanly when startup time itself is unpredictable.

See `solution.md` only after you've formed your own diagnosis.
