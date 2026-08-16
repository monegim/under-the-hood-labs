# Lab 06 — Solutions

## Challenge A — trusting Postgres's own view when the bottleneck is upstream of it

**Check:**
```bash
docker exec -e PGPASSWORD=postgres pglab6-pgbouncer psql -h 127.0.0.1 -p 5432 -U postgres -d pgbouncer -c "SHOW POOLS;"
```
`cl_waiting` for the `appdb` pool is non-zero — clients are actively
queued — while `pg_stat_activity` on the primary showed almost nothing
going on.

**Diagnosis:** `pg_stat_activity` can only ever show you sessions that
have *actually reached Postgres* — a client stuck waiting inside
PgBouncer's queue for a backend connection to free up hasn't gotten
that far yet, so it's completely invisible from the database's own
point of view. Checking only `pg_stat_activity` during a connection
pooler bottleneck is like checking a restaurant's kitchen for how busy
it is while ignoring the line out the door — the kitchen can be nearly
idle while the line is the entire problem. `SHOW POOLS` (and
`SHOW CLIENTS` for individual client-level detail) is the equivalent
view from the pooler's own side, and it's the only place this specific
incident is visible at all.

**Fix:** always check both layers when a pooler sits in front of
Postgres — `pg_stat_activity`/`max_connections` for the database's own
state, `SHOW POOLS`/`SHOW CLIENTS` for the pooler's.

**Lesson:** whenever a request passes through more than one layer with
its own independent capacity limit, checking only the layer you're most
familiar with (usually the database, since that's where DBRE instincts
point first) can actively mislead you into believing everything is
fine. Map out every layer with its own queue/limit *before* an incident,
so you know which commands to run at each one.

---

## Challenge B — session pooling turns 8 clients into 8 permanently-held backends

**Check:**
```bash
docker exec -e PGPASSWORD=postgres pglab6-pgbouncer psql -h 127.0.0.1 -p 5432 -U postgres -d pgbouncer -c "SHOW POOLS;"
```
The pool exhausts just as fast (or faster) than before, and stays
exhausted for the client's *entire connection lifetime* — not just for
the duration of one transaction.

**Diagnosis:** `pool_mode=transaction` (the default in this lab) hands
a backend connection to a client only for the duration of a single
transaction, then immediately returns it to the pool for another client
to use — this is what lets a small pool serve many more logical clients
than its size, as long as they're not all mid-transaction at once.
`pool_mode=session` instead assigns one backend connection to a client
for the client's *entire session* — from connect to disconnect — never
returning it to the pool in between, even during idle time between
queries. With 8 concurrent clients and a pool of 5, session mode
exhausts the pool the moment the 6th client connects, and stays
exhausted until a client fully disconnects, not just finishes a
transaction — which is exactly why it recovers more slowly too.

**Fix:** for this workload (many short-lived, poolable transactions),
`pool_mode=transaction` is the correct choice — session mode is only
appropriate for clients that genuinely need session-level state
(session-scoped temp tables, advisory locks held across statements,
`SET`-based session configuration) that transaction pooling can't
safely preserve across a connection swap.

**Lesson:** `pool_mode` isn't a performance dial to leave on a default —
it's a correctness decision about what session-level guarantees your
application actually needs, and picking the wrong one either breaks
things that rely on session state (transaction mode, if your app
depends on it) or wastes most of the pooling benefit entirely (session
mode, when your app doesn't need it).
