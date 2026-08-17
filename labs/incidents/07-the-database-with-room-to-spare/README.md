# Incident 07 — The Database With Room to Spare

## The page

> Signups have been failing intermittently since this morning - support
> is getting complaints that "create account" just shows an error.
> Someone already pulled up the database's disk usage dashboard: it's
> sitting around 15-20% used. Storage isn't the problem here, so it's
> probably something in the app.

Every reflex points away from "the database ran out of anything" -
the one dashboard anyone thought to check already ruled it out.

## Environment

A small stack, brought up with `docker compose`:
- `app` - a signup-service (`POST /signup`, `GET /health`) that does a
  plain `INSERT` + `COMMIT` against Postgres per request.
- `postgres` - Postgres 16, default configuration otherwise.
- `request-logger` - an unrelated container writing its own small log
  file per "request" for traceability. Nothing in the page mentions
  it, and it never opens a single Postgres file.

You have `docker exec`/`docker logs`/`docker stats` access to every
container, plus the usual host-level tools (`df`, `du`) and a `psql`
client.

## Your task

Find the root cause and fix it. Use whatever tools you'd normally
reach for. There's no prescribed sequence - explore the environment
the way you would a real page, starting from the symptom above.

## Getting unstuck

- The disk-usage dashboard measured *bytes*. Is that the only thing a
  filesystem can run out of?
- `df -h` and `df -i`, run against the same mount, answer two
  genuinely different questions. Try both.
- `request-logger` never opens a single Postgres file and doesn't
  appear anywhere near the database in any diagram. Does "doesn't
  touch the database's files" mean "can't possibly affect the
  database"?

See `solution.md` only after you've formed your own diagnosis, or if
you're completely stuck after trying the nudges above.
