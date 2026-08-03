# Lab 33 — Concept: Dead Tuples, Freezing, and Why Autovacuum Isn't Optional

## What's actually going on

Postgres's MVCC model means an `UPDATE` is really a `DELETE` + `INSERT`
under the hood: the old row version is marked dead (no longer visible to
any new transaction) and a new row version is written. `DELETE` just
marks a row dead without a replacement. Either way, the dead row version
doesn't disappear from disk by itself — it still occupies a slot in a
data page until `VACUUM` processes that page, marks the space reusable,
and updates the visibility map. `pg_stat_user_tables.n_dead_tup` is
Postgres's own running estimate of how many such dead-but-not-yet-reclaimed
row versions exist for a table. Autovacuum is the background process that
normally keeps this number small automatically, triggered per-table once
dead tuples cross a threshold computed from
`autovacuum_vacuum_threshold + autovacuum_vacuum_scale_factor * n_live_tup`.
Turn `autovacuum_enabled` off for a table (a real reloption, not just a
GUC) and that automatic cleanup simply never happens for that table — dead
tuples accumulate without bound, the table's on-disk size grows even
though its row count doesn't, and every sequential scan or index lookup
against it does more I/O than it should for no visible reason in the row
count.

There's a second, independent cost to skipped vacuuming: freezing.
Postgres transaction IDs (XIDs) are a finite 32-bit counter that wraps
around; to make wraparound safe, old-enough row versions get marked
"frozen" (effectively "visible to everyone, forever, regardless of XID
comparison") during vacuum, so the comparison logic never has to reason
about XIDs older than the freeze horizon. `age(relfrozenxid)` tells you
how many transaction IDs have elapsed since a table's oldest unfrozen row
version — the value autovacuum's dedicated wraparound-prevention path
watches against `autovacuum_freeze_max_age` (default 200 million). This
is the one guarantee even `autovacuum_enabled = false` cannot fully
disable in practice: on approach to the wraparound danger zone, Postgres
will force an aggressive, non-cancellable "anti-wraparound" autovacuum
regardless of the table's `autovacuum_enabled` setting or even
cluster-wide `autovacuum = off`, because letting XIDs actually wrap would
mean old committed rows silently appearing to be from the future — a form
of data corruption Postgres refuses to allow. In other words: disabling
autovacuum buys you bloat you have to manually clean up later, not an
actual permanent exemption from vacuuming.

The two challenges show that "is `autovacuum_enabled` true or false" is
the wrong first diagnostic question. A table can have autovacuum nominally
on and still never get vacuumed in practice if its own thresholds
(`autovacuum_vacuum_scale_factor`/`autovacuum_vacuum_threshold`) are tuned
so loose they never trip for that table's actual size — the setting looks
fine, the effective behavior doesn't. Or the table's own settings can be
completely reasonable while `autovacuum_max_workers` (a cluster-wide cap,
not per-table) is saturated by other, larger tables that keep winning the
scheduling contest — a resource-contention problem that has nothing to do
with this table's configuration at all.

## Where this shows up in the real world

"Temporarily" disabling autovacuum on a huge table during a bulk load or
migration — to stop autovacuum from "getting in the way" — is common
advice on forums, and it's genuinely reasonable during the load itself.
The incident happens when nobody re-enables it afterward and runs a
manual `VACUUM` to clear the backlog: months later, the table is several
times its logical size, sequential scans have quietly gotten much slower,
and `age(relfrozenxid)` is well on its way toward a forced,
non-cancellable anti-wraparound vacuum at the worst possible moment (often
during peak traffic, because wraparound risk doesn't wait for a
maintenance window). Separately, `autovacuum_max_workers` contention is a
very real symptom on multi-tenant or many-large-table clusters: teams
correctly tune one table's thresholds and are confused when it still
doesn't get vacuumed on schedule, because the actual bottleneck is
cluster-wide worker capacity, visible only in `pg_stat_activity`.

## Go deeper

- **Book:** *The Internals of PostgreSQL* — Hironobu Suzuki — https://www.interdb.jp/pg/ — the VACUUM Processing chapter covers dead tuples, freezing, and wraparound mechanics in detail.
- **Book:** *PostgreSQL 14 Internals* — Egor Rogov — https://postgrespro.com/community/books/internals — dedicated vacuum and autovacuum chapters, including the worker-scheduling model.
- **Website/docs:** PostgreSQL official docs, routine vacuuming — https://www.postgresql.org/docs/current/routine-vacuuming.html — the authoritative reference for autovacuum thresholds, freezing, and wraparound prevention.
- **Website/docs:** PostgreSQL official docs, `pg_stat_user_tables` — https://www.postgresql.org/docs/current/monitoring-stats.html — the exact columns (`n_dead_tup`, `last_autovacuum`) used throughout this lab.
- **YouTube:** CYBERTEC PostgreSQL — https://www.youtube.com/@CybertecPostgresql — operational content on autovacuum tuning and troubleshooting.
