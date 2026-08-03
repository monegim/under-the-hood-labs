# Incident 01 — Login Latency Spike

## The page

> Latency increased from 8ms to 1.2s. Error rate is 12%. CPU is only 25%.
> Memory looks normal. Customers cannot log in. Find the root cause.

That's the entire page. No hint about which service, no stack trace, no
"MySQL is down" - MySQL is up, and `SELECT 1` against it works fine from
the box.

## Environment

A small web stack, brought up with `docker compose`:
- `app` - a Flask login service (`POST /login`, `GET /health`) fronting
  MySQL through a normal-looking connection pool.
- `mysql` - MySQL 8.0.
- `worker` - a background job container (a "loyalty-points reconciler")
  that also talks to the same MySQL instance.

You have shell access to the host and `docker exec`/`docker logs` into
any of the three containers, plus a `mysql` client and the usual Linux
tools.

## Your task

Find the root cause and fix it. Use whatever tools you'd normally reach
for (`top`, `docker stats`, `mysql` client, `curl`, application logs,
etc.). There's no prescribed sequence of steps here - explore the
environment the way you would a real page, starting from the symptom
above.

## Getting unstuck

- CPU at 25% with 8ms→1.2s latency is a strong hint the bottleneck isn't
  compute at all. What else could a request be waiting on that doesn't
  burn CPU while it waits?
- MySQL being reachable and answering `SELECT 1` quickly doesn't mean
  every connection attempt against it succeeds. Check what MySQL itself
  thinks its current connection load looks like, not just whether it
  responds to a client that already has one.
- The `worker` container isn't mentioned anywhere in the page. Should
  that make you more or less suspicious of it?

See `solution.md` only after you've formed your own diagnosis, or if
you're completely stuck after trying the nudges above.
