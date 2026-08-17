# Lab 31 — Load Balancer Health Check Blind Spot

## Objective
Put three backends behind HAProxy, break one of them in a way that
only shows up in real traffic, and watch the load balancer's own
health checks — and its own dashboard — insist everything is fine the
entire time.

## Why this matters
"Add a health check" sounds like a solved problem the moment a load
balancer stops routing to a backend that's actually down. But a health
check only ever proves what it actually tests, and a shallow one — "is
the process alive," "is the port open" — passes for a backend whose
process is perfectly healthy while the *feature it exists to serve* is
completely broken. That gap is common specifically because the health
check endpoint and the real business logic are usually written,
deployed, and reasoned about separately: a `/healthz` that just returns
`200 OK` is trivial to write correctly once and never touch again,
while the actual application code keeps changing underneath it. The
load balancer isn't lying when it shows a backend as `UP` — it's
telling you exactly what it checked, which turns out not to be the
thing that actually matters.

## Prerequisites
- Docker + the `docker compose` plugin

Check first:
```bash
docker version
docker compose version
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This starts three identical Flask backends behind HAProxy
(round-robin, three servers, one health check). All three answer
`/healthz` correctly. `backend3`'s `/api/data` — the endpoint real
clients actually call — always returns `500`.

## Step 2 — Reproduce the symptom
```bash
for i in $(seq 1 9); do curl -s -o /dev/null -w "%{http_code} " http://localhost:8091/api/data; done; echo
```
Roughly one in three requests comes back `500` — every third one, in
fact, since HAProxy is doing plain round-robin across exactly three
servers.

## Step 3 — Check what the load balancer itself believes
```bash
open http://localhost:8405/    # or just curl it and read the HTML
```
Every backend, including `backend3`, shows `UP`, with a passing health
check and zero failed checks recorded. By every signal HAProxy is
tracking, nothing is wrong.

## Step 4 — Compare what's actually being checked against what's actually broken
```bash
cat haproxy/haproxy.cfg | grep httpchk
```
`option httpchk GET /healthz` — the health check only ever calls the
one endpoint that was never broken. It has no way to know `/api/data`
returns `500`, because it never asks.

## Step 5 — Fix it
```bash
sed -i.bak 's|option httpchk GET /healthz|option httpchk GET /api/data|' haproxy/haproxy.cfg
docker compose restart haproxy
```
Point the health check at (or as close as reasonably possible to) the
thing that actually needs to work.

## Step 6 — Verify
```bash
./check.sh
```
Confirm the stats page agrees too — `backend3` should now show `DOWN`,
out of rotation, while `backend1`/`backend2` keep serving all traffic.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — even a correct health check has a blind spot in time:**
```bash
./reset.sh
docker compose stop backend1
for i in $(seq 1 15); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://localhost:8091/api/data)
  echo -n "$code "
  sleep 0.3
done
echo
```
`backend1` is now fully stopped — about as unambiguously "down" as a
backend gets. Watch the output closely: how many requests actually
fail (`000`) before they stop failing? HAProxy's default health check
doesn't act on a single failed probe — work out why, and what that
means for how long a genuinely dead backend can keep receiving live
traffic even with a completely correct health check pointed at it.

**Challenge B — the check that's even blinder than checking the wrong path:**
```bash
./reset.sh
sed -i.bak 's|option httpchk GET /healthz|#option httpchk GET /healthz|; s|http-check expect status 200|#http-check expect status 200|' haproxy/haproxy.cfg
docker compose restart haproxy
curl -s http://localhost:8405/ | grep -oE '(backend3</a>|[0-9]+s UP|L4OK[^<]*)'
for i in $(seq 1 9); do curl -s -o /dev/null -w '%{http_code} ' http://localhost:8091/api/data; done; echo
```
`backend3` still shows `UP`, now via `L4OK` instead of an HTTP check
result — commenting out `option httpchk` didn't
make this lab's specific problem any worse (it was already blind to
`/api/data`), but figure out exactly what kind of check HAProxy falls
back to with no `httpchk` directive at all, and why that fallback
would still show a backend as healthy even in a *worse* scenario than
this one — say, if `backend3`'s Flask process were still running but
every single route it served, `/healthz` included, returned `500`.

See `solution.md` only after you've formed your own diagnosis.
