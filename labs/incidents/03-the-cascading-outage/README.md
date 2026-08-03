# Incident 03 — The Cascading Outage

## The page

> Orders API is failing almost every request - customers can't confirm
> orders. Error rate is near 100%. Nothing was deployed to orders-service
> today. `docker ps` shows every container "running," including the auth
> service orders depends on.

Every dashboard your team watches is pointed at orders-service, because
that's the customer-facing symptom. Nothing points at anything else.

## Environment

Two small services, brought up with `docker compose`:
- `orders` - the customer-facing API (`GET /orders/<id>`, `GET /health`).
  On every request it calls out to `auth` to validate the caller's
  session before confirming the order.
- `auth` - an internal session-validation service (`POST /validate`,
  `GET /health`) that `orders` depends on.

You have `docker ps`/`docker logs`/`docker exec` access to both
containers, plus `curl` and the usual process/fd inspection tools
(`/proc/<pid>/fd`, `/proc/<pid>/limits`, `ss`, `lsof` if available).

## Your task

Find the root cause and fix it. Use whatever tools you'd normally reach
for (`docker logs`, `docker exec`, `curl`, `/proc/<pid>/limits`, etc.).
There's no prescribed sequence - explore the environment the way you
would a real page, starting from the symptom above.

## Getting unstuck

- `docker ps` showing a container as "running" only means its main
  process hasn't exited. What does that tell you, and *not* tell you,
  about whether it's actually doing its job?
- `orders` is the thing that's alarming, but is it the thing that's
  broken? What does `orders`' own error message, if any, actually say
  about *why* its calls are failing?
- If a process can't open new files or accept new connections, what's
  the first thing you'd check about that specific process, as opposed
  to the service around it?

See `solution.md` only after you've formed your own diagnosis, or if
you're completely stuck after trying the nudges above.
