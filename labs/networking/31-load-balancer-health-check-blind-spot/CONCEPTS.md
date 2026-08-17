# Lab 31 — Concept: A Health Check Only Proves What It Actually Tests

## What's actually going on

A load balancer's health check is not an oracle that knows whether a
backend is "healthy" in any general sense - it's a specific, narrow
test the operator configured, run on a schedule, producing a binary
verdict that everything downstream (routing decisions, dashboards,
alerts) treats as ground truth. That verdict is only ever as good as
the test itself. There are, broadly, three tiers of check in common
use, each proving a strictly different, narrower or wider claim:

- **Layer 4 (TCP connect)**: can a connection be opened to this port
  at all? This is the weakest possible check - it proves a process is
  listening, nothing about what that process actually does once
  connected. A backend that accepts connections and then returns
  garbage, or `500`s on everything, passes a Layer 4 check every time.
- **Layer 7 (HTTP request to a specific path)**: does a real HTTP
  request to *this one endpoint* get back an expected response? This
  proves the application layer is alive and that specific code path
  works - and says nothing whatsoever about any other endpoint, unless
  that endpoint happens to exercise the same dependencies.
- **Deep/dependency-aware health checks**: a health endpoint that
  itself queries the database, checks a cache connection, or otherwise
  exercises the same critical dependencies real traffic needs. This is
  the only tier that can catch "the process is fine, a thing it
  depends on isn't" - and it's also the tier most often skipped,
  because it's the most work to build and keep in sync with reality.

Each tier is a strict superset of the failures the one below it can
catch, and none of them is "the health check" in some absolute sense -
they're different, deliberately-scoped promises, and a load balancer
showing a backend as `UP` is only ever reporting that the *specific
promise it was configured to check* held true at the last check
interval. Nothing about that status claims anything wider.

Detection is also never instantaneous, independent of which tier of
check is used. A health check runs on an interval, and most
implementations (HAProxy included) require multiple *consecutive*
failures before flipping a server to `DOWN` - a deliberate hedge
against a single dropped probe or one slow response causing
unnecessary, disruptive flapping. That hedge has a real, quantifiable
cost: a backend that goes from perfectly healthy to completely dead in
an instant still receives, and fails, some number of real requests
during the `fall × interval` window before the load balancer's own
verdict catches up to reality. A "correctly configured" health check
and "zero requests ever hit a dead backend" are two different
guarantees, and only one of them is actually achievable.

## Where this shows up in the real world

"Add a health check" is treated as a solved, one-time task far more
often than it should be, precisely because a shallow check (Layer 4,
or a static Layer 7 endpoint that returns `200` unconditionally) is
trivial to write once and never revisit - while the application logic
it's meant to represent keeps changing underneath it indefinitely. The
gap between what the check tests and what the application actually
does grows silently, with nothing forcing anyone to notice, until a
real backend-specific failure (a bad deploy, a lost database
connection scoped to one instance, a corrupted local config) slips
straight through a check that's still technically passing. This is
one of the more common root causes behind "the dashboard was all green
and customers were still getting errors" incidents - not because
monitoring lied, but because it was faithfully reporting the answer to
a narrower question than anyone realized it was actually asking.

## Go deeper

- **Website/docs:** HAProxy documentation, "Health checking" — https://www.haproxy.org/download/2.9/doc/configuration.txt (search `option httpchk`) — the authoritative reference for `httpchk`, `inter`/`rise`/`fall`, and the Layer 4 fallback behavior this lab is built around.
- **Website/docs:** HAProxy blog, "Health Checks" — https://www.haproxy.com/blog/ — HAProxy's own team has written extensively and practically about designing real health checks, not just enabling them.
- **Book:** *Site Reliability Engineering* — Google, ed. Betsy Beyer et al. (free at https://sre.google/books/) — the chapters on monitoring distributed systems cover exactly this class of "the signal is real, but it's answering the wrong question" failure.
- **Website/docs:** Kubernetes documentation, "Configure Liveness, Readiness and Startup Probes" — https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/ — the same Layer4/Layer7/dependency-aware distinction, in the context this lab's lesson most commonly gets rediscovered in.
- **Article:** Julia Evans, "Sometimes health checks are more complicated than they look" (search the exact title on jvns.ca) — a widely-referenced, practically-grounded piece on exactly this failure mode.
