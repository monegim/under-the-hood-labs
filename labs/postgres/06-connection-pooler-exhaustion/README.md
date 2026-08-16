# Lab 06 — Connection Pooler Exhaustion

## Objective
Watch new clients queue behind PgBouncer's own connection pool — a
completely separate, smaller limit than Postgres's own
`max_connections` — and learn to check the layer that's actually
constrained instead of the one everyone remembers to check.

## Why this matters
`max_connections` is the number most people think of when a database
"runs out of connections" — but the moment a connection pooler
(PgBouncer, pgcat, PgBouncer-in-a-sidecar) sits in front of Postgres,
there are *two* independent connection ceilings stacked on top of each
other: how many clients the pooler will accept, and how many *backend*
connections the pooler is configured to hand out to Postgres at once.
The second number is very often much smaller than the first, and much
smaller than `max_connections` — which means an app can be completely
starved for connections while Postgres itself reports 95% of its
capacity sitting idle.

## Prerequisites
- Docker + the `docker compose` plugin

Check first:
```bash
docker version
docker compose version
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This brings up Postgres (`max_connections=100`) behind PgBouncer in
transaction-pooling mode with `default_pool_size=5`, then launches 8
clients through PgBouncer that each open a transaction and hold it for
60 seconds — 3 more than the pool has backend connections for.

## Step 2 — Reproduce the symptom
```bash
time docker exec -e PGPASSWORD=postgres pglab6-pgbouncer psql -h 127.0.0.1 -p 5432 -U postgres -d appdb -c "SELECT 1;"
```
This hangs for a while before finally completing (or times out,
depending on how long you wait) — a plain `SELECT 1`, on a database
that's otherwise doing almost nothing.

## Step 3 — Check the wrong layer first (on purpose)
```bash
docker exec pglab6-primary psql -U postgres -c \
  "SELECT count(*) AS active_connections, current_setting('max_connections') FROM pg_stat_activity;"
```
Barely a handful of connections, nowhere close to `max_connections`.
Postgres itself looks completely healthy — which is exactly why this
incident is confusing if you stop looking here.

## Step 4 — Check the layer that's actually constrained
```bash
docker exec -e PGPASSWORD=postgres pglab6-pgbouncer psql -h 127.0.0.1 -p 5432 -U postgres -d pgbouncer -c "SHOW POOLS;"
```
PgBouncer has its own special admin database (`pgbouncer`) you connect
to with a normal `psql` client to run commands like `SHOW POOLS`,
`SHOW CLIENTS`, `SHOW SERVERS`. Look at `cl_active` (clients currently
being served) vs `cl_waiting` (clients queued, waiting for a pooled
backend connection to free up) for the `appdb` pool.

## Step 5 — Fix it
```bash
docker compose stop pgbouncer
DEFAULT_POOL_SIZE=20 docker compose up -d pgbouncer
```
(Raising the pool size is the immediate lever here — the real fix in
production is usually sizing `default_pool_size` against how many
*concurrent, in-flight* transactions your app actually needs served at
once, not against `max_connections`.)

## Step 6 — Verify
```bash
time docker exec -e PGPASSWORD=postgres pglab6-pgbouncer psql -h 127.0.0.1 -p 5432 -U postgres -d appdb -c "SELECT 1;"
docker exec -e PGPASSWORD=postgres pglab6-pgbouncer psql -h 127.0.0.1 -p 5432 -U postgres -d pgbouncer -c "SHOW POOLS;"
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — trusting Postgres's own view when the bottleneck is upstream of it:**
```bash
./reset.sh
sleep 5
docker exec pglab6-primary psql -U postgres -c "SELECT * FROM pg_stat_activity WHERE datname='appdb';"
```
This alone tells a misleadingly reassuring story. Before concluding
anything about whether the database is "fine," what's the one command
against the *pooler itself* you should always run alongside this, and
why would relying on `pg_stat_activity` alone during this specific
incident actively point you in the wrong direction?

**Challenge B — session pooling turns 8 clients into 8 permanently-held backends:**
```bash
docker compose stop pgbouncer
POOL_MODE=session docker compose up -d pgbouncer
```
Re-run the 8-client flood from `setup.sh`'s pattern (or just re-run
`./setup.sh` after this — it'll restart pgbouncer in session mode).
Compare how quickly the pool gets exhausted, and for how long, versus
the original transaction-mode behavior. Explain exactly what
`pool_mode=session` changes about *when* a client gives its backend
connection back to the pool, and why that makes exhaustion both easier
to trigger and slower to recover from.

See `solution.md` only after you've formed your own diagnosis.
