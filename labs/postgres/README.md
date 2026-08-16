# Level 4 — Databases: PostgreSQL

Eight hands-on PostgreSQL incidents, each a real docker-compose environment
with an induced fault, not a quiz. Same DBRE instinct as the
[MySQL half of this level](../mysql): reproduce the incident, diagnose it
from first principles using Postgres's own system views, fix it, then work
through two follow-up challenges that look identical on the surface but
have a different root cause.

## Labs

1. [`01-replication-lag`](01-replication-lag) — streaming replication
   primary/standby, replay lag induced by contention on the standby's own
   host. Localize the lag with `pg_stat_replication` on the primary and
   `pg_last_wal_receive_lsn()` vs `pg_last_wal_replay_lsn()` on the
   standby — is it the network/receive side or the replay/apply side?
2. [`02-wal-full`](02-wal-full) — `pg_wal` fills a bounded disk because an
   inactive replication slot pins old WAL segments and prevents recycling.
   `pg_replication_slots` and `restart_lsn` as the diagnostic, dropping the
   slot as the fix.
3. [`03-autovacuum-disabled`](03-autovacuum-disabled) — a table with
   autovacuum turned off accumulates dead tuples silently. `n_dead_tup` in
   `pg_stat_user_tables`, `age(relfrozenxid)` as the wraparound-risk
   signal, manual `VACUUM`/`VACUUM FREEZE` as the fix.
4. [`04-index-bloat`](04-index-bloat) — repeated updates/deletes bloat a
   btree index without the row count changing at all. Detecting bloat with
   `pgstattuple`, fixing it online with `REINDEX CONCURRENTLY` instead of a
   lock-everything plain `REINDEX`.
5. [`05-lock-contention`](05-lock-contention) — a session left idle in an
   open transaction holds a row lock and blocks everything behind it.
   `pg_stat_activity`, `pg_blocking_pids()`, `pg_terminate_backend()`, and
   `idle_in_transaction_session_timeout` as prevention.
6. [`06-connection-pooler-exhaustion`](06-connection-pooler-exhaustion) —
   PgBouncer's own pool fills up while Postgres itself sits nearly idle.
   `SHOW POOLS`/`SHOW CLIENTS` on the pooler as the diagnostic layer
   `pg_stat_activity` alone can't see, `pool_mode` as the correctness
   decision underneath it.
7. [`07-transaction-id-wraparound-emergency`](07-transaction-id-wraparound-emergency) —
   autovacuum disabled server-wide lets `age(relfrozenxid)` cross
   `autovacuum_freeze_max_age` with nothing left to catch it. Manual
   `VACUUM FREEZE` as the immediate fix, and why `ALTER SYSTEM` +
   `pg_reload_conf()` can't undo a command-line-pinned setting.
8. [`08-logical-replication-conflict`](08-logical-replication-conflict) —
   a single duplicate-key conflict halts an entire logical replication
   subscription, not just the offending row. `pg_stat_subscription` as the
   diagnostic, resolving the conflict vs. `ALTER SUBSCRIPTION ... SKIP`'s
   data-loss tradeoff.

## Prerequisites

- Docker + the `docker compose` plugin
- Labs 2 and later also need a small amount of `sudo` access on the host
  (for a loop-mounted scratch filesystem) — each README says exactly when
  and why.

Same per-lab file set as [Level 1](../linux) and
[Level 2](../networking): `README.md`, `solution.md`, `CONCEPTS.md`,
`setup.sh`, `check.sh`, `reset.sh`.
