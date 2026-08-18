# Incident 09 — The Shared Proxy Meltdown

## The page

> service-a is throwing connection errors, intermittently at first and
> now almost constantly. CPU and memory on service-a's own host look
> completely normal. Nothing in service-a's deployment history changed
> today. Support is also mentioning something about an internal tool
> ("service-b") being slow, but that's a separate, lower-priority
> system nobody thinks is related.

Two services, one incident report about the important one, one
unrelated-sounding complaint about a system nobody thinks matters.

## Environment

A single VM running:
- `service-a.service` — a trivial HTTP service on `:6001`. This is the
  actual subject of the page.
- `service-b.service` — a completely separate, lower-priority internal
  service on `:6002`, whose one endpoint is currently stuck.
- `nginx`, listening on `:8080`, proxying `/a/` to `service-a` and
  `/b/` to `service-b` — the *same* nginx instance, in front of both.

You have `curl`, `systemctl`, and normal shell access to everything on
the box.

## Your task

Find the root cause and fix it. Use whatever tools you'd normally
reach for. There's no prescribed sequence — explore the environment
the way you would a real page, starting from the symptom above.

## Getting unstuck

- Test `service-a` two different ways: through `http://127.0.0.1:8080/a/`,
  and directly against `http://127.0.0.1:6001/`. Do they agree?
- Both services are proxied by the exact same `nginx` process. Does
  "these are two unrelated services" have to mean "nothing either of
  them does can affect the other"?
- `nginx -T` (or reading `/etc/nginx/nginx.conf` directly) shows every
  setting currently in effect, including ones that default to a value
  nobody explicitly typed. Check what governs how many connections a
  single `nginx` worker can hold open at once — and whether that
  number is shared or split up per `location`.

See `solution.md` only after you've formed your own diagnosis, or if
you're completely stuck after trying the nudges above.
