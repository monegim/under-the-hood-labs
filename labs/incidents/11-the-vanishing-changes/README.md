# Incident 11 — The Vanishing Changes

## The page

> Support has escalated a cluster of tickets over the past few days: users
> say they update their profile note, see it save successfully, and then
> minutes later it's back to the old value - or gone entirely. It doesn't
> happen to everyone, and nobody can reproduce it on demand. Engineering
> has checked the application logs and the database's error log - nothing.
> No errors, no deletes, no crashes.

Nothing failed. Nothing errored. The save call itself always returns
"saved." Whatever's happening, it's happening quietly, after the response
has already gone back to the user.

## Environment

A small stack, brought up with `docker compose`:
- `app` - a notes service (`POST /save`, `GET /note/<id>`, `GET /health`)
  sitting in front of MySQL.
- `primary` - MySQL 8.0, the source of truth for writes.
- `replica` - MySQL 8.0, replicating from `primary`, read-only.
- `reporting-job` - an unrelated container doing its own heavy disk writes.
  Nothing in the page mentions it.

You have `docker exec`/`docker logs`/`docker stats` access to every
container, a `mysql` client, and the usual host tools (`iostat`, `curl`).

## Your task

Find the root cause and fix it. Use whatever tools you'd normally reach
for (`curl`, `mysql` client's `SHOW REPLICA STATUS`, `docker stats`, etc.).
There's no prescribed sequence - explore the environment the way you would
a real page, starting from the symptom above.

## Getting unstuck

- "Saves succeed, but the value sometimes reverts a moment later, with
  nothing in any error log" - is data actually being deleted anywhere, or
  might two different reads of "the same" data be looking at two different
  places?
- The app talks to two MySQL instances, not one. Which one does `POST
  /save` write to, and which one does `GET /note/<id>` read from? Are you
  sure they're the same one?
- `SHOW REPLICA STATUS\G` on the replica, checked right after you `POST` a
  change, will tell you directly whether the replica has actually caught
  up to that write yet - don't assume, look.

See `solution.md` only after you've formed your own diagnosis, or if
you're completely stuck after trying the nudges above.
