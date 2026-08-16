# Lab 06 — Concept: Two Independent Connection Ceilings

## What's actually going on

`max_connections` governs how many concurrent connections *Postgres
itself* will accept, full stop — every one of those connections costs
real server-side resources (each Postgres backend is its own OS
process, with its own memory footprint), which is exactly why
`max_connections` is usually set conservatively rather than raised
freely to "just fix" connection problems. A connection pooler like
PgBouncer sits as a proxy in front of that limit specifically to let
many more *client-side* connections exist than Postgres's own backend
processes could ever sustain, by multiplexing them: many app-side
connections share a much smaller number of actual Postgres backend
connections, handed out and reclaimed based on the pooler's own
`pool_mode`.

This means a pooled deployment genuinely has two separate, independently
configured capacity limits stacked on top of each other:
`max_connections` on the Postgres side, and `default_pool_size` (times
however many distinct pools/databases/users) on the pooler side. They
are not the same number, are not automatically kept in any particular
ratio, and — critically — a client can be completely blocked by the
smaller one while the larger one sits almost entirely unused, which is
exactly what this lab demonstrates. Nothing about Postgres's own
metrics or logs will show this state, because from Postgres's
perspective, nothing unusual is happening at all — the queued clients
simply haven't arrived yet.

`pool_mode` decides the granularity at which a backend connection gets
reassigned between clients. `session` mode ties one backend to one
client for the client's whole connection lifetime — simple, and
correctly preserves anything session-scoped (temp tables,
`SET`-configured session variables, advisory locks spanning multiple
statements), but offers essentially no multiplexing benefit, since
"pooled" connections are functionally just direct connections with an
extra hop. `transaction` mode reassigns the backend at transaction
boundaries instead — a client only holds a backend connection while
actively inside `BEGIN`...`COMMIT`, freeing it up for someone else the
instant a transaction ends — which is what lets a small pool genuinely
serve far more clients than its size, but breaks anything that depends
on session state persisting between transactions on what the app
assumes is "its own" connection, since the underlying backend can
literally be a different Postgres process for the next statement.

## Where this shows up in the real world

Connection pooler exhaustion masquerading as "the database is
overloaded" is an extremely common false diagnosis in production —
teams reach for scaling up Postgres (more `max_connections`, a bigger
instance) when the actual constraint is a pooler configuration nobody
has looked at since it was first deployed, often years earlier, sized
for a very different traffic pattern than the application now produces.
It's also a common source of confusing intermittent errors specifically
when an application's connection pool (on the app side) is itself sized
larger than the database pooler's pool — the app believes it has
plenty of headroom to open connections, and each one queues invisibly
at the PgBouncer layer instead.

## Go deeper

- **Website/docs:** PgBouncer official documentation — https://www.pgbouncer.org/config.html — authoritative reference for `pool_mode`, `default_pool_size`, and every `SHOW` admin command.
- **Website/docs:** PgBouncer FAQ — https://www.pgbouncer.org/faq.html — covers `pool_mode` tradeoffs and common gotchas directly, including session-state caveats under transaction pooling.
- **Website/docs:** PostgreSQL official docs — https://www.postgresql.org/docs/current/runtime-config-connection.html — `max_connections` and related connection settings reference.
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors (O'Reilly) — frames connection management and pooling as first-class production reliability concerns.
- **YouTube:** CYBERTEC PostgreSQL — https://www.youtube.com/@CybertecPostgresql — has PgBouncer/connection-pooling-focused operational content.
