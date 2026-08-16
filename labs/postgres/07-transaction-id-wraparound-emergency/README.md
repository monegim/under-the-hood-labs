# Lab 07 — Transaction ID Wraparound Emergency

## Objective
Push a table's `age(relfrozenxid)` past `autovacuum_freeze_max_age` with
autovacuum disabled server-wide, then fix it the way an actual emergency
gets fixed — and discover that the obvious "just turn autovacuum back
on" move doesn't do what you'd expect.

## Why this matters
Postgres identifies every row version by a 32-bit transaction ID.
That counter wraps around eventually, and if the database ever let it
wrap without freezing old rows first, already-committed data would
suddenly look like it was written "in the future" and vanish. Autovacuum
normally freezes old rows continuously so this is a non-issue — but if
autovacuum is disabled (a common real incident: turned off during a
bulk load or migration and never turned back on) there is nothing left
running that watches this at all. This isn't a hypothetical: real
production Postgres instances have hit forced read-only shutdowns from
exactly this, and by the time you notice, you're not tuning a setting,
you're in an incident.

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
This brings up Postgres with `autovacuum=off` and
`autovacuum_freeze_max_age=100000` (Postgres's actual hard minimum for
this setting — the real default is 200,000,000; see `CONCEPTS.md` for
why lowering it is an honest simulation and not a shortcut around the
mechanism). It then creates a `counters` table and burns ~110,000
transactions against a single row, pushing `age(relfrozenxid)` for that
table past the threshold.

## Step 2 — Confirm the age
```bash
docker exec pglab7-primary psql -U postgres -d appdb -c \
  "SELECT relname, age(relfrozenxid) FROM pg_class WHERE relname = 'counters';"
```
This is well past the 100000 threshold. Normally, crossing this
threshold is exactly when an *anti-wraparound autovacuum* would kick in
automatically and freeze the table, regardless of any per-table
autovacuum setting. Check whether anything did:
```bash
docker logs pglab7-primary 2>&1 | grep -i "aggressive vacuum to prevent wraparound"
```
Nothing. `autovacuum=off` doesn't just skip *this* table — it means the
autovacuum launcher process isn't running at all, so there's no daemon
left to force anything.

## Step 3 — Fix the immediate emergency
```bash
docker exec pglab7-primary psql -U postgres -d appdb -c "VACUUM FREEZE counters;"
```
A manual `VACUUM FREEZE` does exactly what an anti-wraparound autovacuum
would have done — freezes eligible rows and advances `relfrozenxid` —
without touching server configuration or restarting anything.

## Step 4 — Verify
```bash
./check.sh
```
`age(relfrozenxid)` should now be back near 0.

## Step 5 — Prevent it from happening again
```bash
docker compose stop primary
AUTOVACUUM=on docker compose up -d primary
docker exec pglab7-primary psql -U postgres -d appdb -c "SHOW autovacuum;"
```
This recreates the container with autovacuum re-enabled going forward.
Note that this required a container restart — see Challenge A for why
the "obvious" live fix doesn't work here.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the live fix that silently does nothing:**
```bash
./reset.sh
docker exec pglab7-primary psql -U postgres -d appdb -c "ALTER SYSTEM SET autovacuum = on;"
docker exec pglab7-primary psql -U postgres -d appdb -c "SELECT pg_reload_conf();"
docker exec pglab7-primary psql -U postgres -d appdb -c "SHOW autovacuum;"
```
This is the standard, correct way to flip a `sighup`-context GUC live,
with no restart and no dropped connections — and it reports success.
But `SHOW autovacuum` still says `off`, and `age(relfrozenxid)` never
moves. Look at how `autovacuum` was set in `docker-compose.yml` (not
`postgresql.conf`), and work out where that setting sits in Postgres's
configuration-precedence order relative to `ALTER SYSTEM` — and why
`pg_reload_conf()` can't override it no matter how many times you call
it.

**Challenge B — a long-running transaction caps what `VACUUM FREEZE` can do:**
```bash
./reset.sh
docker exec -d pglab7-primary psql -U postgres -d appdb -c \
  "BEGIN; SELECT * FROM counters; SELECT pg_sleep(90);"
sleep 2
docker exec pglab7-primary psql -U postgres -d appdb -c "CALL burn_xids(5000);"
docker exec pglab7-primary psql -U postgres -d appdb -c "SELECT age(relfrozenxid) FROM pg_class WHERE relname='counters';"
docker exec pglab7-primary psql -U postgres -d appdb -c "VACUUM FREEZE counters;"
docker exec pglab7-primary psql -U postgres -d appdb -c "SELECT age(relfrozenxid) FROM pg_class WHERE relname='counters';"
```
`VACUUM FREEZE` completes without error, and the age drops — but not to
0, and not below whatever it was when the background transaction
started. Find the still-open transaction in `pg_stat_activity` (it'll be
the one with a multi-second `xact_age` and `state = 'active'`), and
explain why a transaction that hasn't touched `counters` at all can
still cap how far `VACUUM FREEZE` is able to advance `relfrozenxid` for
rows written *after* it began.

See `solution.md` only after you've formed your own diagnosis.
