# Incident 08 — The IPv6-Only Timeouts

## The page

> Customers report checkout is "slow" - every request eventually
> completes, nobody's actually failing to check out, but it now
> consistently takes 5+ seconds instead of feeling instant. Started
> sometime today, no deploy correlates with it. CPU, memory, and error
> rates on every service look completely normal - there are no errors
> to look at, just a delay nobody can explain.

Nothing crashed. Nothing errored. Every request succeeds. It's just
slower than it used to be, by an oddly specific, oddly consistent
amount.

## Environment

A small stack, brought up with `docker compose`, on a dual-stack
Docker network (`enable_ipv6: true`):
- `frontend` - a checkout-service (`POST /checkout`, `GET /health`)
  that calls `backend` over HTTP using its hostname, resolved via
  Docker's own DNS.
- `backend` - a Flask service listening on both IPv4 and IPv6,
  handling the actual checkout logic.

You have `docker exec`/`docker logs` access to both containers, plus
the usual host-level tools (`curl`, `ping`) and a Python interpreter
inside each container.

## Your task

Find the root cause and fix it. Use whatever tools you'd normally
reach for. There's no prescribed sequence - explore the environment
the way you would a real page, starting from the symptom above.

## Getting unstuck

- Time a request directly: `curl -s -w '\ntotal: %{time_total}s\n' -X
  POST http://localhost:8090/checkout`. Is the delay closer to "a
  little slow" or suspiciously close to a specific, round number?
- `backend` has an address on two separate IP protocols. Does every
  test you run confirm *both* of them work, or just one?
- "The network path is reachable" and "a specific port on that path
  responds" are two different claims. `ping`/`ping6` only tests the
  first one.

See `solution.md` only after you've formed your own diagnosis, or if
you're completely stuck after trying the nudges above.
