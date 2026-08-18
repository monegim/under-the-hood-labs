# Incident 09 — Solution

## Root cause

`nginx` is proxying both `service-a` and `service-b` from a single
worker process with `worker_connections 8` — a small number here
specifically to make this reproduce fast, but the mechanism is
identical at any scale. Every proxied request consumes connection
slots from that one shared pool for as long as it's in flight — one
for the client's connection to `nginx`, one for `nginx`'s connection
to the backend. `service-b`'s endpoint never returns a response, so
every request sent to it holds its slots open indefinitely. A handful
of concurrent requests into `service-b` is enough to consume the
entire pool, and once it's exhausted, `nginx` has no connections left
to accept *anything* — including brand-new requests for `service-a`,
which has done nothing wrong and would answer in milliseconds if it
were ever actually reached.

## Why it happened

`service-a` and `service-b` are logically unrelated — different code,
different teams, different purpose — which makes "one broke the other"
feel like it shouldn't be possible. But logical independence and
infrastructure independence are two different things, and nothing
about how this `nginx` instance was configured gives either service
its own dedicated capacity. `worker_connections` is a property of the
`nginx` worker process as a whole, consumed by whatever's currently in
flight regardless of which `location` block it matches — from
`nginx`'s point of view there's one connection budget, not two.

## Why the obvious fixes don't work

- **Restarting `service-a`**: does nothing — `service-a` was never the
  problem; it's not even reached while the pool is exhausted, so
  there's nothing on its side for a restart to fix.
- **Restarting `nginx`**: temporarily frees the pool, but the exact
  same requests (or the next batch) refill it within seconds, since
  `service-b`'s endpoint is still hung and nothing about a restart
  changes that.
- **Raising `worker_connections`**: raises the number of concurrent
  hung requests it takes to reproduce this, but doesn't change the
  underlying fact that `service-b`'s hung requests and `service-a`'s
  legitimate ones are still drawing from one shared, finite pool — at
  a large enough scale (or with slightly more concurrent load against
  `service-b`), the exact same meltdown recurs. This delays the
  incident; it doesn't fix it.
- **Setting `proxy_connect_timeout` on `service-b`'s location**: looks
  like exactly the right kind of fix, and doesn't work here —
  `service-b` accepts the TCP connection instantly (its process is
  alive and listening; it just never sends a response), so the
  *connect* phase always succeeds immediately and this timeout never
  has anything to fire on.

## The investigation

Confirm the symptom, and confirm it's specific to the proxy, not
`service-a` itself:
```bash
curl -s -m 3 -o /dev/null -w "via nginx: %{http_code}\n" http://127.0.0.1:8080/a/
curl -s -m 3 -o /dev/null -w "direct:    %{http_code}\n" http://127.0.0.1:6001/
```
`service-a` fails through `nginx`, succeeds instantly when hit
directly — proof the problem is in the proxy layer, not `service-a`
itself.

Check what `nginx` is actually configured with:
```bash
sudo nginx -T 2>/dev/null | grep -E "worker_connections|proxy_pass|proxy_.*timeout"
```
A small, shared `worker_connections`, both services proxied from the
same worker, and no timeout at all set on `service-b`'s `location` —
nothing bounds how long a single hung request there can hold its slots.

Confirm `service-b` is the one actually holding connections open:
```bash
sudo ss -tnp | grep :6002
```
Multiple established connections to `service-b`'s port, sitting there
indefinitely.

## The fix

Edit `/etc/nginx/nginx.conf` and add a real response timeout to
`service-b`'s `location` block specifically:
```
location /b/ {
    proxy_pass http://127.0.0.1:6002/;
    proxy_read_timeout 3s;
}
```
```bash
sudo nginx -t && sudo systemctl reload nginx
```
This doesn't make `service-b`'s underlying problem go away — it still
hangs — but it bounds how long any single request to it can occupy a
shared connection slot. `service-a` now recovers within a few seconds
of any burst against `service-b`, instead of staying starved for as
long as `service-b` stays hung (which, with nothing bounding it, could
be indefinitely).

The durable fix is architectural: give services that don't need to
share fate a proxy layer (or at minimum a `location`-scoped connection
limit) that can't let one starve the other's capacity, no matter how
badly either one misbehaves on its own.

## Real-world examples of this pattern

- Any reverse proxy or API gateway with a single worker pool in front
  of multiple backend services reproduces this exact incident shape
  the moment one backend starts hanging instead of failing fast —
  `worker_connections`/`max_conns`/thread-pool-style limits are common
  across nginx, HAProxy, and most API gateways, and all of them are
  shared budgets unless explicitly partitioned per backend.
- This is the same underlying mechanism as
  `labs/networking/17-conntrack-exhaustion` (a shared, finite resource
  exhausted by one workload starving everyone else using it) and
  `labs/networking/31-load-balancer-health-check-blind-spot` (a load
  balancer's own view of "healthy" not matching what real traffic
  experiences) — here the two combine: nothing *reports* unhealthy
  (both services' processes are alive), and the actual failure is a
  shared-capacity problem invisible to any check that only looks at
  one service in isolation.
- "An unrelated internal tool took down our main API" is a recurring,
  specifically embarrassing incident shape precisely because the
  connection is almost never obvious from either side's own metrics —
  it only becomes visible once someone thinks to check the shared
  layer sitting between both of them.
