# Incident 03 — Concept: Resource Exhaustion in One Service, Symptom in Another

## What's actually going on

The Linux mechanism here is exactly `labs/linux/16-too-many-open-files`:
every process has a finite `RLIMIT_NOFILE`, `open()` (and `accept()`,
and socket creation) fails with `EMFILE` the instant that ceiling is
hit, and nothing about that failure is specific to file descriptors in
the "disk file" sense - sockets, pipes, and file descriptors are the
same kernel resource. A process that leaks any of them, slowly or
quickly, hits the identical wall.

What makes this an *incident-level* lesson rather than just a repeat of
lab 16 is the **service boundary** the leak sits behind. `auth-service`
degrades in a way that is completely invisible from outside its own
process: it doesn't crash, it doesn't restart, `docker ps` reports it as
running the entire time, and its own error handling is "correct" in the
narrow sense that it catches the `OSError` and returns a clean HTTP
response instead of crashing. But that clean-looking `500` is
functionally identical to `auth` being down, from the perspective of
everything that depends on it. `orders-service` has no way to distinguish
"auth rejected this validation because the session is invalid" from
"auth is internally falling apart" - both arrive as an HTTP error, and
`orders` correctly (from its own narrow point of view) reports that its
dependency failed. The result is that 100% of the *visible, alerting*
failure shows up on a service (`orders`) that has no bug in it at all,
while the actual broken component sits one hop upstream, quietly
returning fast, well-formed error responses that don't look like a
crash to anything watching from outside.

This is the general shape of cascading failure in any dependency graph:
a resource-exhaustion problem contained entirely within one node becomes
a correctness/availability problem for every node downstream of it, and
the monitoring/alerting surface for a system is very often concentrated
on the user-facing edges of that graph, not on every internal node
individually - which means the first responder's dashboards point,
correctly, at the wrong service to start with.

## Where this shows up in the real world

Any service mesh, microservice architecture, or even a monolith calling
out to a handful of internal dependencies (auth, feature flags,
config service, session store, an internal search index) has this
shape: a slow leak or resource cap on one internal dependency, invisible
to `docker ps`/`kubectl get pods`/basic liveness probes, cascades into
user-facing error rates on whatever's closest to the customer. Real
incidents in this category are a major reason distributed tracing
(so you can see *which hop* in a request actually failed, not just that
the edge service returned an error) and per-dependency health checks
(exercising the real code path, not a trivial 200 OK) exist as
practices - both exist specifically because "the container is running"
and "the container is doing its job" are different claims, and only one
of them is what `docker ps`/basic liveness checks actually verify.

## Go deeper

- **Book:** *Site Reliability Engineering* — Google, ed. Betsy Beyer et
  al. (free at https://sre.google/books/) — see the chapters on
  cascading failures and on monitoring distributed systems, both
  directly about this incident's shape.
- **Book:** *Systems Performance* — Brendan Gregg — the general
  discipline of checking the resource that's actually exhausted (here,
  file descriptors on one specific process) rather than the service
  that's most visibly alarming.
- **Website:** Brendan Gregg's site — https://www.brendangregg.com — the
  USE method applied per-process (not just per-host) is exactly what
  catches "one process's file descriptors are saturated" before it's
  obvious from the outside.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man2/open.2.html
  and https://man7.org/linux/man-pages/man5/proc.5.html — document
  `EMFILE`/`ENFILE` and the `/proc/<pid>/limits` and `/proc/<pid>/fd`
  interfaces used to diagnose this.
