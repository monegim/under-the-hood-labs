# Incident 06 — Concept: What "Rollout Succeeded" Actually Means

## What's actually going on

A Kubernetes Deployment's rollout is considered successful based on one
thing: whether the new ReplicaSet's pods pass their **readiness probe**
within the configured thresholds. That's the entire contract —
`kubectl rollout status` is watching `.status.conditions` on the
Deployment, which is derived from pods transitioning to `Ready`, which
is derived from the readiness probe returning success. Nothing in that
chain has any concept of "does this service correctly perform its
actual job" — readiness answers exactly one question, "should this pod
receive traffic right now," and Kubernetes has no built-in mechanism for
"is this pod's *response* to that traffic correct." A probe that checks
`GET /healthz` and a probe that checks "can this service complete a real
checkout" are two fundamentally different claims, and Kubernetes only
ever evaluates the first one — the second is entirely the responsibility
of whoever wrote the probe (or, as here, however deliberately shallow
they decided to make it).

This is not an oversight in Kubernetes' design — it's deliberate, and
for good reason. If a liveness probe transitively depended on every
downstream system a service talks to (its database, a cache, another
microservice), then an outage in any one of those dependencies would
cause Kubernetes to start killing and restarting otherwise-healthy pods
of every *dependent* service, potentially turning one outage into many,
compounding a single failure across your whole architecture. So the
convention — liveness probes especially should be cheap, local, and
narrow ("is this process alive and able to serve HTTP at all") — exists
specifically to prevent that failure-amplification pattern. The cost of
that design choice is exactly what this incident demonstrates: a probe
narrow enough to avoid amplifying failures is, by the same property,
too narrow to catch a real class of failures on its own.

The typo itself (`DB_PASSWROD` vs `DB_PASSWORD`) is possible at all
because Kubernetes environment variables are just arbitrary key/value
strings from the platform's point of view — there's no schema
validation tying a Deployment's env var names to what the application
code inside the container actually reads. `kubectl apply` will happily
accept any name; the container starts fine; the process starts fine;
only the specific code path that calls
`os.environ.get("DB_PASSWORD", "")` and gets back the empty-string
default instead of erroring notices anything is wrong — and even then,
only when a request that needs it actually arrives.

## Where this shows up in the real world

"The deployment succeeded, the dashboards are green, and customers are
still filing tickets" is one of the most common gaps between
infrastructure-level health (is the process running, is the pod Ready)
and business-level health (is the thing the process is *for* actually
working) in production Kubernetes environments — config typos, missing
secrets, wrong feature-flag values, and broken downstream dependencies
all share this exact shape: invisible to a shallow probe, immediately
visible to a real request. It's why many mature deployment pipelines
add an explicit post-deploy smoke test or canary-traffic verification
step as a separate gate from "pods reached Ready," and why some teams
build richer readiness checks specifically for the services where a
false "healthy" is expensive enough to be worth the added coupling risk
this pattern deliberately avoids by default.

## Go deeper

- **Website/docs:** Kubernetes official docs — https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-probes — the authoritative reference for what liveness/readiness/startup probes actually check and how a Deployment's rollout status is derived from them.
- **Website/docs:** Kubernetes official docs — https://kubernetes.io/docs/tutorials/kubernetes-basics/deploy-app/deploy-intro/ — the basic model of what a Deployment rollout considers "done."
- **Book:** *Site Reliability Engineering* — Google, ed. Betsy Beyer et al. (free online at https://sre.google/books/) — covers the general principle of monitoring business-facing signals (SLIs tied to real user outcomes) rather than infrastructure proxies alone, directly relevant to why this incident's `check.sh` verifies real `/checkout` calls instead of pod status.
- **YouTube:** That DevOps Guy (Marcel Dempers) — https://www.youtube.com/@MarcelDempers — hands-on Kubernetes content covering probes, rollouts, and deployment strategies.
