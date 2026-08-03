# Incident 04 — The Database That Hangs

## The page

> Customers report that "save" and "checkout" actions just spin for
> several seconds before completing, some time out entirely. Reads and
> page loads are fine. No errors in the application logs. CPU and memory
> on the database host both look completely normal.

Nothing crashed. Nothing is erroring. Something that used to be
instant now just... takes a while, specifically for anything that
writes.

## Environment

A small stack, brought up with `docker compose`:
- `app` - a save-service (`POST /save`, `GET /health`) that does a plain
  `INSERT` + `COMMIT` against MySQL per request.
- `mysql` - MySQL 8.0, default configuration.
- `backup-job` - an unrelated container doing its own disk writes.
  Nothing in the page mentions it.

You have `docker exec`/`docker logs`/`docker stats` access to every
container, plus the usual host-level tools (`iostat`, `top`, `df`) and a
`mysql` client.

## Your task

Find the root cause and fix it. Use whatever tools you'd normally reach
for (`docker stats`, `iostat`, `mysql` client's `SHOW PROCESSLIST`,
etc.). There's no prescribed sequence - explore the environment the way
you would a real page, starting from the symptom above.

## Getting unstuck

- "Reads are fine, writes are slow, CPU/memory look normal" - what
  resource does a *write* specifically depend on that a *read* mostly
  doesn't?
- `SHOW PROCESSLIST` on MySQL, run while a slow save is actually
  in-flight, will show you exactly which phase of the write the
  connection is stuck in - don't guess, look.
- `backup-job` isn't mentioned in the page and doesn't touch MySQL's
  data files at all. Does "doesn't touch the database" mean "can't
  possibly affect the database"?

See `solution.md` only after you've formed your own diagnosis, or if
you're completely stuck after trying the nudges above.
