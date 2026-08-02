# Lab 31 — Concept: Replay Lag Is a Symptom, Not a Diagnosis

## What's actually going on

Postgres streaming replication splits the work of "keep the standby
current" into two genuinely separate stages, run by two separate
processes on the standby. The **walreceiver** process connects to the
primary and streams raw WAL bytes into the standby's own `pg_wal`
directory — this is close to a sequential append and is cheap. The
**startup process**, running in permanent recovery mode, reads that WAL
and replays it against the standby's actual heap and index files —
`INSERT`/`UPDATE`/`DELETE`/`VACUUM` effects reapplied one WAL record at a
time. That second step needs the same kind of random-access read/write
I/O a live workload would need, because it's doing the same page-level
work the primary already did. `pg_last_wal_receive_lsn()` tells you how
far the first stage has gotten; `pg_last_wal_replay_lsn()` tells you how
far the second has gotten. When people say "replication lag" they usually
mean the gap between the primary's current WAL position and
`pg_last_wal_replay_lsn()` — but that single number conflates two
independently-failing stages, which is exactly why this lab has you check
both.

`pg_stat_replication` on the PRIMARY gives you `write_lag`, `flush_lag`,
and `replay_lag` as actual `interval` values (added in PG10) — computed
from timestamps embedded in the standby's periodic feedback messages, so
you don't even need to log into the standby to know replay is falling
behind. But to find out WHY, you have to go to the standby itself and ask
whether it has received the WAL it's slow to replay
(`pg_last_wal_receive_lsn()`, `pg_stat_wal_receiver`) or whether receipt
is fine and replay itself is stuck.

The main lab and Challenge A demonstrate two different resource-layer
causes for replay-side lag specifically — receipt stays healthy in both,
only replay suffers. Disk I/O contention (main lab, via `io-hog`'s
`dd ... conv=fdatasync` writers sharing the same underlying block device
as the standby's actual PGDATA) slows the startup process's page writes
directly. CPU contention (Challenge A, via `yes` loops pinning every core)
starves the startup process of scheduling time instead — the disk is
fine, but the process doing replay simply doesn't get to run enough.
Challenge B is a different category of cause entirely: a **recovery
conflict**. A `REPEATABLE READ` transaction on the standby fixes a
snapshot at `BEGIN` and must be able to see every row version visible
under that snapshot for as long as it's open. If the primary's `VACUUM`
removes a row version the standby's open transaction still needs, replay
of that removal has to either wait for the standby's query to finish (up
to `max_standby_streaming_delay`) or cancel the query outright. With
`hot_standby_feedback=off` (the default) and no long transaction, this
almost never happens — it takes a long-running standby query PLUS
concurrent vacuum activity on the primary touching the same rows to
surface it, and when it does, CPU and disk on the standby are both
completely idle, because the bottleneck isn't a resource at all —
`pg_stat_database_conflicts` is the one view built specifically to reveal
it.

## Where this shows up in the real world

Read replicas that run long analytical queries are a very common,
very real setup — and `hot_standby_feedback` is the exact knob that
trades primary-side bloat for standby-side replication stalls (or vice
versa). A team that turns on long-running reporting queries against a
standby without understanding this trade-off will eventually see
replication lag with a perfectly healthy-looking standby host, and burn
time checking `iostat`/`top` before anyone thinks to check
`pg_stat_database_conflicts`. Meanwhile, disk and CPU contention on a
standby sharing a host/disk/hypervisor with other workloads is an
everyday noisy-neighbor problem in any environment where database
infrastructure isn't fully isolated — the correct instinct is the same
order every time: check the standby's own OS-level resource usage first
(cheap, and often the actual answer), and only then look at Postgres's
own MVCC/locking state if hardware comes back clean.

## Go deeper

- **Book:** *The Internals of PostgreSQL* — Hironobu Suzuki — https://www.interdb.jp/pg/ — the WAL and physical replication chapters cover exactly how the walreceiver/startup-process split works internally.
- **Book:** *Database Reliability Engineering* — Laine Campbell & Charity Majors (O'Reilly) — the "check the host before the database config" diagnostic discipline this whole lab is built around.
- **Website/docs:** PostgreSQL official docs, replication config — https://www.postgresql.org/docs/current/runtime-config-replication.html — `hot_standby_feedback`, `max_standby_streaming_delay`, and related settings, straight from the source.
- **Website/docs:** PostgreSQL official docs, `pg_stat_replication` and standby-side stats — https://www.postgresql.org/docs/current/monitoring-stats.html — the exact columns used throughout this lab (`replay_lag`, `pg_stat_wal_receiver`, `pg_stat_database_conflicts`).
- **YouTube:** CYBERTEC PostgreSQL — https://www.youtube.com/@CybertecPostgresql — operational content on replication and recovery-conflict troubleshooting.
