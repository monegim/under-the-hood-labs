# Lab 31 — Solution

## Root cause

HAProxy's health check is configured as `option httpchk GET /healthz`
— it periodically opens a connection to each backend, issues that one
specific request, and marks the backend `UP` if it gets back the
expected status. `backend3`'s `/healthz` handler is completely
independent code from its `/api/data` handler; nothing about the
latter being broken changes what the former returns. The health check
passes because it was never testing the thing that's actually broken
— it's doing exactly what it was configured to do, faithfully and
correctly, on a question that doesn't matter to real traffic.

## Why it happened

A minimal `/healthz` — "return `200`, unconditionally" — is trivial to
write once, rarely needs to change, and is easy to treat as
"the health check, done." The actual business logic it's supposed to
be a proxy for keeps evolving independently: new dependencies, new
failure modes, new code paths that can break in ways `/healthz` was
never written to detect. The two drift apart not because anyone made
an active mistake, but because nothing forces them to stay connected
— a shallow health check that passed correctly on day one keeps
"passing correctly" on the exact same narrow question forever, even as
the thing it was meant to represent stops being true.

## Why the obvious fixes don't work

- **Restarting `backend3`**: does nothing - the underlying bug (in
  this lab, `BROKEN=true`) is part of its configuration/deployment,
  not a transient state a restart clears.
- **Restarting HAProxy**: also does nothing on its own - it re-reads
  the same `httpchk GET /healthz` config and reaches the exact same
  wrong conclusion about `backend3` every time.
- **Adding more backends**: dilutes the failure rate (one bad backend
  among four instead of three) but doesn't fix anything - the broken
  backend is still `UP`, still in rotation, still failing its share of
  real requests indefinitely.
- **Removing `backend3` from the config by hand**: fixes the symptom
  for exactly as long as nobody touches the config again, and doesn't
  address why the health check failed to catch this - the next
  genuinely-broken-but-healthz-passing backend hits the exact same
  blind spot.

## The investigation

Confirm the symptom - real traffic actually failing:
```bash
for i in $(seq 1 9); do curl -s -o /dev/null -w "%{http_code} " http://localhost:8091/api/data; done; echo
```

Check what the load balancer itself believes:
```bash
curl -s http://localhost:8405/ | grep -oE '(backend[123]</a>|[0-9]+s UP|[0-9]+s DOWN)'
```
Every backend shows `UP`.

Compare the health check's target against what's actually broken:
```bash
grep httpchk haproxy/haproxy.cfg
```
`/healthz` - a completely different endpoint from `/api/data`, the one
actually failing.

## The fix

```bash
sed -i.bak 's|option httpchk GET /healthz|option httpchk GET /api/data|' haproxy/haproxy.cfg
docker compose restart haproxy
```
`backend3` starts failing its health check within one check interval
and is pulled out of rotation - `/api/data` now succeeds 100% of the
time, served entirely by `backend1`/`backend2`.

In a real system, checking the exact production endpoint directly
usually isn't ideal either (it has side effects, or depends on
external state a health check shouldn't need) - the durable version of
this fix is a dedicated `/healthz` (or `/readyz`) endpoint that
*actually exercises* the same dependencies and code paths the real
traffic depends on, kept in sync with what "healthy" really means as
the application evolves, rather than a static `200 OK` that was only
ever accurate on the day it was written.

---

## Challenge A — even a correct health check has a blind spot in time

**Check:**
```bash
docker compose stop backend1
for i in $(seq 1 15); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://localhost:8091/api/data)
  echo -n "$code "
  sleep 0.3
done
```
Several `000` (connection failed) responses appear before they stop -
even though `backend1` is unambiguously, completely down.

**Diagnosis:** HAProxy's default health check doesn't act on a single
failed probe - by default it requires several *consecutive* failures
(the `fall` threshold) before marking a server down, checked on a
fixed interval (`inter`, 2 seconds by default). This exists on
purpose: a health check is itself a network request, and a single
dropped packet or one slow response shouldn't be enough to yank a
perfectly healthy backend out of rotation - averaging over a few
consecutive checks makes the health-check system itself resilient to
noise. The cost of that resilience is a real, bounded window - roughly
`fall × inter` seconds - during which a backend that just died keeps
receiving a share of live traffic and failing every one of those
requests, no misconfiguration required at all.

**Fix:** this isn't something to "fix" away entirely (an
instant-on-one-failure check trades false negatives for false
positives), but it can be tuned deliberately:
```
server backend1 backend1:5000 check inter 1s fall 2 rise 2
```
A shorter interval and lower `fall` count shrinks the detection
window at the cost of being more sensitive to transient blips -
exactly the kind of tradeoff that should be a conscious choice, not a
default nobody looked at.

**Lesson:** "the health check is correctly configured" and "traffic
never hits a dead backend" are not the same guarantee - there's always
a real detection-lag window built into any check that isn't instant
and infinitely sensitive, and a specific number of real requests will
fail inside it every time a backend genuinely dies, however well the
check itself is written.

---

## Challenge B — the check that's even blinder than checking the wrong path

**Check:**
```bash
sed -i.bak 's|option httpchk GET /healthz|#option httpchk GET /healthz|; s|http-check expect status 200|#http-check expect status 200|' haproxy/haproxy.cfg
docker compose restart haproxy
curl -s http://localhost:8405/ | grep -oE '(backend3</a>|[0-9]+s UP|L4OK[^<]*)'
```
`backend3` still shows `UP` - but now via `L4OK`, not an HTTP status.

**Diagnosis:** `check` alone, with no `option httpchk`, tells HAProxy
to do a Layer 4 check only - open a TCP connection to the port and
close it again. That's it. It never sends an HTTP request and never
looks at a response body or status code at all - it only proves the
process is accepting TCP connections on that port. This is strictly
blinder than the main lab's mistake: checking the wrong HTTP path at
least confirms the HTTP server itself is alive and answering
something. A pure TCP check would show a backend as `UP` even in a
strictly worse scenario than this lab's - a Flask process that's still
running but returns `500` for every single route, `/healthz` included,
looks identical to a perfectly healthy one from a Layer 4 check's
point of view, because nothing about that failure prevents the TCP
handshake itself from succeeding.

**Fix:** restore `option httpchk` (Layer 7). At minimum, an HTTP-level
check catches "the process is up but the application itself is
broken" - a strictly larger class of real failures than a TCP check
can ever see.

**Lesson:** "the load balancer shows it as `UP`" is not one fixed
guarantee - it means something different depending on what kind of
check produced that status, and the weakest form (a bare TCP connect)
is common as an *unintentional* default: removing or never adding
`option httpchk` quietly downgrades every backend's health guarantee
without changing a single line that looks like it should matter.
