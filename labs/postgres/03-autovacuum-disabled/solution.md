# Lab 33 — Solutions

## Challenge A — the switch is "on," but the thresholds never trip

**Check:**
```bash
docker exec lab33-primary psql -U postgres -d appdb -c \
  "SELECT reloptions FROM pg_class WHERE relname = 'accounts';"
docker exec lab33-primary psql -U postgres -d appdb -c "
  SELECT n_live_tup, n_dead_tup, last_autovacuum FROM pg_stat_user_tables WHERE relname = 'accounts';
"
```
`reloptions` shows `{autovacuum_vacuum_scale_factor=0.8,autovacuum_vacuum_threshold=100000}`
— no `autovacuum_enabled=false` anywhere. `last_autovacuum` is still
`NULL` and `n_dead_tup` is still climbing.

**Diagnosis:** autovacuum decides whether to vacuum a table using a
threshold formula: it triggers once
`n_dead_tup > autovacuum_vacuum_threshold + autovacuum_vacuum_scale_factor * n_live_tup`.
Defaults are `threshold=50`, `scale_factor=0.2` — for a 2,000-row table
that's `50 + 0.2*2000 = 450` dead tuples before autovacuum fires. This
challenge set `threshold=100000` and `scale_factor=0.8`
(`100000 + 0.8*2000 = 101600` dead tuples needed) — a bar this table's
actual workload will basically never clear. The table is textbook bloated
and autovacuum is, by every technical definition, "enabled" — it's simply
configured to be so conservative that it might as well be off.

**Fix:**
```bash
docker exec lab33-primary psql -U postgres -d appdb -c "
  ALTER TABLE accounts RESET (autovacuum_vacuum_scale_factor, autovacuum_vacuum_threshold);
  VACUUM (VERBOSE, ANALYZE) accounts;
"
```

**Lesson:** "is autovacuum enabled?" is the wrong first question — check
the per-table reloptions (`autovacuum_vacuum_scale_factor`,
`autovacuum_vacuum_threshold`, and the analyze/freeze equivalents) against
the table's actual size and churn rate. A table can have autovacuum
fully "on" and still never get vacuumed in practice if the thresholds
don't match reality.

---

## Challenge B — correctly configured, but starved of workers

**Check:**
```bash
docker exec lab33-primary psql -U postgres -d appdb -c "
  SELECT relname, n_dead_tup, last_autovacuum FROM pg_stat_user_tables
  WHERE relname IN ('accounts','noisy_a','noisy_b');
"
docker exec lab33-primary psql -U postgres -c \
  "SELECT pid, state, query FROM pg_stat_activity WHERE query ILIKE 'autovacuum:%';"
docker exec lab33-primary psql -U postgres -c "SHOW autovacuum_max_workers;"
```
`pg_stat_activity` shows `autovacuum: VACUUM noisy_a` and
`autovacuum: VACUUM noisy_b` running essentially back-to-back, one at a
time. `autovacuum_max_workers` is `1`. `accounts`' `last_autovacuum`
lags far behind `noisy_a`/`noisy_b`'s, or is still null, even though its
own thresholds are perfectly reasonable.

**Diagnosis:** `autovacuum_max_workers` caps how many autovacuum worker
processes can run cluster-wide at once (default 3, set to 1 in this
challenge). When more tables cross their dead-tuple threshold than there
are workers to service them, the autovacuum launcher just queues the rest
— it doesn't prioritize by table importance or wait time, only by need.
Two large, heavily-churned tables (`noisy_a`, `noisy_b`) can keep the
single available worker continuously busy, so `accounts` never gets a
turn even though it's correctly configured and genuinely needs one. This
is the exact same shape of lesson as noisy-neighbor CPU/disk contention in
the replication labs, just applied to autovacuum's own worker pool
instead of the OS scheduler.

**Fix:**
```bash
docker exec lab33-primary psql -U postgres -c "ALTER SYSTEM SET autovacuum_max_workers = 3;"
docker restart lab33-primary
# wait for healthy, then:
docker exec lab33-primary psql -U postgres -d appdb -c "VACUUM (VERBOSE, ANALYZE) accounts;"
```
In production this is a capacity-planning problem, not a one-table fix:
size `autovacuum_max_workers` (and `autovacuum_vacuum_cost_limit`, which
governs how fast each worker is allowed to go) for the number and size of
tables that actually need regular vacuuming, and consider
`autovacuum_vacuum_cost_delay`/per-table cost overrides to keep any one
big table's autovacuum from monopolizing a worker for too long.

**Lesson:** a table's own autovacuum settings being "correct" isn't
sufficient — autovacuum is a shared, capacity-limited resource
(`autovacuum_max_workers`) across the whole cluster. A small,
well-configured table can still starve if other tables are consuming all
the available workers, and the only place that's visible is
`pg_stat_activity` (what's actually running right now) compared against
`pg_stat_user_tables.last_autovacuum` (what hasn't run in a while).
