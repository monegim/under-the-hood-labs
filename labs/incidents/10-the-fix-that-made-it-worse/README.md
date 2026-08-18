# Incident 10 — The Fix That Made It Worse

## The page

> Checkout has a known, accepted failure rate during traffic bursts —
> around 40%, stable, and it always recovers between bursts. That's
> been true for as long as anyone can remember. Right now it's sitting
> at 100% and hasn't recovered in several minutes. Someone mentions
> that retry-on-failure was added to the checkout client recently,
> specifically to *reduce* how often customers see an error.

The "fix" shipped days ago. Nobody's connected it to this until now —
it was supposed to make things better, and for a while, arguably
looked like it did.

## Environment

A single VM running:
- `backend.service` — a small HTTP service with a genuinely fixed,
  finite capacity (a handful of concurrent workers, a fixed amount of
  real work per request). It was always sized for average load, not
  peak load — some failed requests during a traffic burst are
  expected and have always been tolerated.
- `client-traffic.service` — stands in for real checkout traffic:
  periodic bursts, every couple of seconds, forever, the same
  recurring pattern this service has always seen. Each failed
  checkout attempt is retried automatically, immediately, up to a
  configured number of times.

You have `systemctl`, `journalctl`, and normal shell access to
everything on the box.

## Your task

Find the root cause and fix it. Use whatever tools you'd normally
reach for. There's no prescribed sequence — explore the environment
the way you would a real page, starting from the symptom above.

## Getting unstuck

- `backend.service`'s own capacity hasn't changed — it's the same
  fixed size it's always been. If the *service* didn't get any
  smaller, what else could make its *effective* load bigger?
- Compare two numbers from `client-traffic`'s own logs: how many
  *checkout attempts* it's making, versus how many *HTTP requests*
  it's actually sending. Do those numbers still roughly match each
  other, the way they always would have before?
- Something was changed recently specifically to make error rates
  *better*. Check what's actually configured on `client-traffic.service`
  right now, and consider whether "reduces how often any one user sees
  an error" and "reduces total load on the backend" are always the
  same goal.

See `solution.md` only after you've formed your own diagnosis, or if
you're completely stuck after trying the nudges above.
