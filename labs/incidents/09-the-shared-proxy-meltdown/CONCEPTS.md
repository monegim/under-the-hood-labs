# Incident 09 — Concept: Shared Infrastructure Has No Concept of "Unrelated"

## What's actually going on

Two mechanisms combine here: a proxy's connection budget being a
single shared pool rather than something partitioned per backend, and
the difference between a *connect* failure and a *response* failure —
which is exactly the gap a naive timeout choice falls straight into.

`nginx` (like most reverse proxies and load balancers) allocates a
fixed number of connections per worker process — `worker_connections`
— and every request proxied through that worker draws from the exact
same pool, regardless of which `location` block or which backend it's
headed to. There's no default notion of "`service-a`'s share" versus
"`service-b`'s share"; the pool is simply consumed by whatever's
currently in flight. A request holds its slots for as long as it's
in flight, end to end — from the moment the client connects until a
response is fully sent back (or the connection is torn down some other
way). A backend that never responds at all — not slow, not erroring,
just silent — holds those slots open indefinitely, because nothing
about "no response yet" looks different to the proxy from "response is
still being generated, keep waiting." Once enough requests are stuck
in that state to consume the entire pool, the proxy has no capacity
left for anything else routed through that same worker, including
requests to a completely unrelated, perfectly healthy backend.

This is why the specific *kind* of timeout matters, not just whether a
timeout exists. A `connect` timeout guards the phase where the proxy
is trying to establish a TCP connection to the backend — it does
nothing for a backend that accepts that connection instantly and then
simply never sends data, because from the connect phase's point of
view, nothing went wrong. A `read` (or `response`) timeout guards the
phase after the connection is already established, while the proxy is
waiting for the backend to actually send something — this is the
phase a genuinely "hung" backend gets stuck in, and it's the only
timeout of the two that can ever fire for that failure mode. Treating
"add a timeout" as a single, interchangeable fix — without checking
which phase of the request lifecycle is actually the one hanging —
produces a change that looks like a fix, passes a quick sanity check
(the connect phase genuinely does succeed fast), and does nothing for
the actual incident.

## Where this shows up in the real world

Any shared proxy, API gateway, or load balancer sitting in front of
multiple backend services carries this risk by default, and it scales
with how many unrelated services get consolidated behind one instance
for operational convenience — the more services share one proxy, the
larger the blast radius any single misbehaving one can cause. It's a
particularly easy incident to miss in monitoring specifically because
neither side looks broken by itself: the proxy process is running, the
struggling backend's process is running (just not responding), and the
victim service's own health checks and resource metrics are completely
normal, because it was never actually reached. The only place the
actual mechanism is visible is the proxy's own connection-level state —
exactly the layer a "check each service's own dashboard" runbook is
least likely to include.

## Go deeper

- **Website/docs:** nginx documentation, "Module ngx_http_core_module" — https://nginx.org/en/docs/http/ngx_http_core_module.html — `worker_connections` and the full set of `proxy_*_timeout` directives, including the connect/send/read distinction this incident hinges on.
- **Website/docs:** nginx documentation, "ngx_http_proxy_module" — https://nginx.org/en/docs/http/ngx_http_proxy_module.html — `proxy_connect_timeout`, `proxy_read_timeout`, `proxy_send_timeout` defined precisely, each guarding a different phase.
- **Book:** *Site Reliability Engineering* — Google, ed. Betsy Beyer et al. (free at https://sre.google/books/) — the chapters on cascading failures and shared infrastructure isolation cover exactly this class of blast-radius incident.
- **Related lab:** [`labs/networking/17-conntrack-exhaustion`](../../networking/17-conntrack-exhaustion) — the same "shared, finite resource exhausted by one workload" mechanism, one layer lower in the stack (a router's connection-tracking table instead of a proxy's worker connection pool).
- **Related lab:** [`labs/networking/31-load-balancer-health-check-blind-spot`](../../networking/31-load-balancer-health-check-blind-spot) — a load balancer's own view of "healthy" not matching what real traffic experiences, the other half of why this incident shape is so easy to miss until it's already severe.
