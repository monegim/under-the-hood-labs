# Lab 33 — Autovacuum Disabled: Silent Bloat and Wraparound Risk

## Objective
Watch dead tuples pile up on a table with `autovacuum_enabled = false`,
learn to spot it via `pg_stat_user_tables`, and understand why nobody
turning autovacuum back on is a complete fix by itself — you still have
to clean up the backlog it left behind.

## Why this matters
Postgres uses MVCC: an `UPDATE` never modifies a row in place, it writes
a whole new row version and marks the old one dead once no transaction
can see it anymore. `DELETE` just marks a row dead outright. Those dead
row versions still occupy disk pages until `VACUUM` reclaims them for
reuse — normally autovacuum does this automatically in the background.
Turn it off for a table (a common but dangerous move to "avoid autovacuum
pauses during a migration" or "stop it from interfering with a bulk
load") and dead tuples simply accumulate: the table bloats, sequential
scans get slower for no apparent reason, and — the sharper edge — the
table's rows stop getting frozen, which is one input into the cluster's
overall transaction ID wraparound risk. None of this shows up in row
counts. It only shows up if you know to check
`pg_stat_user_tables.n_dead_tup`.

## Prerequisites
- Docker + the `docker compose` plugin

Check first:
```bash
docker version
docker compose version
```

## Step 1 — Bring up the incident
```bash
chmod +x setup.sh
./setup.sh
```
This script:
1. Starts a single Postgres instance via `docker compose`.
2. Creates an `accounts` table with `WITH (autovacuum_enabled = false)`
   and seeds it with 2,000 rows.
3. Runs a bounded (50-iteration) full-table `UPDATE` workload — every
   iteration rewrites every row, generating 2,000 dead tuples per pass
   that autovacuum is configured to never clean up.

## Step 2 — See the misleading signal
```bash
docker exec lab33-primary psql -U postgres -d appdb -c "SELECT count(*) FROM accounts;"
```
Still 2,000 rows. Row count tells you nothing is wrong.

## Step 3 — Check the real signal
```bash
docker exec lab33-primary psql -U postgres -d appdb -c "
  SELECT relname, n_live_tup, n_dead_tup, last_autovacuum, last_vacuum
  FROM pg_stat_user_tables WHERE relname = 'accounts';
"
```
> Gotcha: `n_dead_tup` should be tens of thousands, and `last_autovacuum`
> should be `NULL` — autovacuum has never touched this table, exactly as
> configured. Compare physical size to the live row count:
```bash
docker exec lab33-primary psql -U postgres -d appdb -c \
  "SELECT pg_size_pretty(pg_total_relation_size('accounts'));"
```
A 2,000-row table taking up space for tens of thousands of row versions
is bloat, plain and simple.

## Step 4 — Confirm the config, not just the symptom
```bash
docker exec lab33-primary psql -U postgres -d appdb -c \
  "SELECT reloptions FROM pg_class WHERE relname = 'accounts';"
```
`{autovacuum_enabled=false}` — confirmed at the source, not guessed from
symptoms.

## Step 5 — Fix it
Re-enable autovacuum for future changes, AND manually clean up the
existing backlog — re-enabling alone does nothing retroactively:
```bash
docker exec lab33-primary psql -U postgres -d appdb -c \
  "ALTER TABLE accounts RESET (autovacuum_enabled);"
docker exec lab33-primary psql -U postgres -d appdb -c \
  "VACUUM (VERBOSE, ANALYZE) accounts;"
```
Confirm:
```bash
docker exec lab33-primary psql -U postgres -d appdb -c "
  SELECT relname, n_live_tup, n_dead_tup, last_vacuum FROM pg_stat_user_tables WHERE relname = 'accounts';
"
```
`n_dead_tup` should drop to near zero. For a table that's also
approaching real wraparound risk (check with the query below), use
`VACUUM FREEZE` instead, which additionally marks old-enough row versions
frozen so they stop counting against transaction ID age at all:
```bash
docker exec lab33-primary psql -U postgres -d appdb -c "
  SELECT relname, age(relfrozenxid) FROM pg_class WHERE relname = 'accounts';
"
```
`age(relfrozenxid)` is the number of transaction IDs that have elapsed
since this table was last fully frozen — the value autovacuum's
wraparound-prevention logic watches, compared against
`autovacuum_freeze_max_age` (default 200 million). This lab's workload
won't get anywhere near that threshold for real (driving it there
legitimately means consuming hundreds of millions of transaction IDs) —
treat the query above as "this is the number you'd monitor in production,"
not something you'll watch cross a real danger line here.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — autovacuum is "on" but never fires anyway:**
```bash
docker exec lab33-primary psql -U postgres -d appdb -c "
  ALTER TABLE accounts RESET (autovacuum_enabled);
  ALTER TABLE accounts SET (autovacuum_vacuum_scale_factor = 0.8, autovacuum_vacuum_threshold = 100000);
"
docker exec lab33-primary bash -c '
  for i in $(seq 1 50); do
    psql -U postgres -d appdb -c "UPDATE accounts SET balance = balance + 1;" >/dev/null
  done
'
```
`pg_stat_user_tables` shows the same bloat symptom, and
`reloptions` no longer says `autovacuum_enabled=false` anywhere. Diagnose
why autovacuum still never ran, using the per-table settings, not just
the on/off switch.

**Challenge B — autovacuum is correctly configured, but starved:**
```bash
docker exec lab33-primary psql -U postgres -c "ALTER SYSTEM SET autovacuum_max_workers = 1;"
docker restart lab33-primary
# wait for it to become healthy again, then create two noisy-neighbor tables:
docker exec lab33-primary psql -U postgres -d appdb -c "
  CREATE TABLE noisy_a (id SERIAL PRIMARY KEY, data TEXT);
  CREATE TABLE noisy_b (id SERIAL PRIMARY KEY, data TEXT);
  INSERT INTO noisy_a (data) SELECT repeat('x', 500) FROM generate_series(1, 200000);
  INSERT INTO noisy_b (data) SELECT repeat('x', 500) FROM generate_series(1, 200000);
"
docker exec lab33-primary bash -c '
  for i in $(seq 1 20); do
    psql -U postgres -d appdb -c "UPDATE noisy_a SET data = repeat(chr(65+(random()*25)::int),500);" >/dev/null &
    psql -U postgres -d appdb -c "UPDATE noisy_b SET data = repeat(chr(65+(random()*25)::int),500);" >/dev/null &
    psql -U postgres -d appdb -c "UPDATE accounts SET balance = balance + 1;" >/dev/null
    wait
  done
'
```
`accounts` has a normal, sane autovacuum configuration this whole time —
`autovacuum_enabled` is unset (default true), scale factor and threshold
are both defaults. Yet `last_autovacuum` for `accounts` barely moves.
Figure out what's actually eating the autovacuum capacity, and what
`pg_stat_activity` shows about it while it's happening.

See `solution.md` only after you've formed your own diagnosis.
