# Lab 16 — Concept: Probes Are Just Timers kubelet Trusts Completely

## What's actually going on

Kubelet doesn't know anything about what your application actually does —
it only knows what a probe tells it, on the schedule you gave it, taken
completely at face value. A `livenessProbe` is kubelet asking, on a
loop, "should I consider this container dead?" — `periodSeconds` sets how
often it asks, `timeoutSeconds` sets how long it'll wait for an answer
before counting that attempt as a failure, and `failureThreshold` sets
how many consecutive failures it takes before kubelet actually kills the
container and lets the normal restart policy bring up a fresh one. None
of those numbers have anything to do with whether the app is actually
broken; they're just a timer configuration, and if that timer is tighter
than the app's real (and often perfectly normal) response-time
variance, kubelet will faithfully kill a completely healthy container on
schedule, over and over, exactly as configured. This is why
`CrashLoopBackOff` caused by a bad probe looks identical, from the
outside, to `CrashLoopBackOff` caused by a real bug — the only way to
tell them apart is `kubectl describe pod`'s Events section, which shows
kubelet's own actions (`Killing`, `Started`) as distinct entries you can
line up against the probe's configured timing, plus checking whether
`kubectl logs --previous` shows the app failing on its own or being cut
off mid-request by something external.

The readiness/liveness distinction matters because the two probes don't
just have different *purposes*, they have completely different
*consequences* on failure. A failing `readinessProbe` only changes one
thing: whether the pod's IP stays in the `Endpoints`/`EndpointSlice`
objects a Service uses to route traffic. The container itself is left
completely alone — still running, still consuming resources, just
temporarily excluded from getting new traffic until it starts passing
again. A failing `livenessProbe`, by contrast, ends the container's life
immediately once the threshold is hit; kubelet sends a
`SIGTERM`/`SIGKILL` and the kubelet's normal restart logic starts a new
one. This is why a too-tight readinessProbe just makes a service flap in
and out of rotation — annoying, maybe a source of dropped requests
mid-flap, but not destructive — while a too-tight livenessProbe on the
exact same app can turn "occasionally slow" into "constantly restarting
and never actually settling," because every restart also resets whatever
warm state (caches, open connections, JIT-compiled code paths) made the
app fast in the first place, sometimes making the *next* startup even
slower and more probe-failure-prone than the last.

`startupProbe` exists specifically to solve the case this lab's second
challenge covers: an app whose *startup* time is long or unpredictable,
which is a different problem than an app whose *steady-state* response
time is occasionally long. Without a `startupProbe`, the only knob
available is `initialDelaySeconds` on the livenessProbe — a single fixed
guess, made once, that either wastes time waiting past a startup that
usually finishes faster, or (as reproduced in Challenge B) kills the
container repeatedly because the real startup time exceeds the guess.
A `startupProbe` instead runs its own probe/threshold cycle first, and
kubelet doesn't even start evaluating the livenessProbe until the
startupProbe reports success — turning "guess how long startup takes"
into "actually check when startup finishes."

## Where this shows up in the real world

This is one of the single most common self-inflicted incidents in
production Kubernetes: probe timing copied from a template, a different
service's manifest, or a tutorial, without being tuned to the actual
app's latency profile. It gets worse under exactly the conditions where
you'd most want stability — a traffic spike or a noisy-neighbor CPU
steal on the node slows every request down slightly, which pushes a
marginal livenessProbe over its threshold, which kills containers, which
adds *more* load to the remaining replicas (and cold-starts on the new
ones), which slows things down further. A probe misconfiguration that
was invisible under light load can turn a real but survivable traffic
spike into a full outage purely through this feedback loop, and the
first responder paged into it often burns the first 20 minutes looking
for an application bug that was never there.

## Go deeper

- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-probes — the authoritative reference on liveness/readiness/startup probes and their exact fields.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/ — a hands-on task guide covering `startupProbe` and probe tuning specifically.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/debug/ — general troubleshooting task index this lab's diagnostic sequence follows.
- **Book:** *Kubernetes in Action* — Marko Lukša — covers probe semantics and common misconfigurations in depth.
- **Book:** *Kubernetes Patterns* — Bilgin Ibryam & Roland Huß (O'Reilly) — the "Health Probe" pattern chapter covers exactly this readiness-vs-liveness distinction.
- **YouTube:** That DevOps Guy (Marcel Dempers) — https://www.youtube.com/@MarcelDempers — hands-on probe/health-check troubleshooting videos.
